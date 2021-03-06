//
//  Decoder.swift
//  redis
//
//  Created by John Connolly on 2018-12-26.
//

import Foundation
import NIO


let newline: UInt8 = 0xA
let carriageReturn: UInt8 = 0xD
let plus: UInt8 = 0x2B
let dollar: UInt8 = 0x24
let asterisk: UInt8 = 0x2A
let hyphen: UInt8 = 0x2d
let colon: UInt8 = 0x3a

extension String: Error { }

final class Decoder: ByteToMessageDecoder {

    var cumulationBuffer: ByteBuffer?

    public typealias InboundOut = RedisData

    func decode(ctx: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        var position = 0
        switch try parse(at: &position, from: buffer) {
        case .notYetParsed:
            return .needMoreData
        case let .parsed(redisData):
            ctx.fireChannelRead(wrapInboundOut(redisData))
            buffer.moveReaderIndex(forwardBy: position)
            return .continue
        }
    }


    func parse(at position: inout Int, from buffer: ByteBuffer) throws -> PartialRedisData {
        guard let token = buffer.peekBytes(at: position, length: 1)?.first else {
            return .notYetParsed
        }
        position += 1
        switch token {
        case plus:
            guard let string = try parseSimpleString(at: &position, from: buffer) else { return .notYetParsed }
            return .parsed(.basicString(string))
        case hyphen:
            guard let string = try parseSimpleString(at: &position, from: buffer) else { return .notYetParsed }
            let error = "problem:" + string
            return .parsed(.error(error))
        case colon:
            guard let number = try integer(at: &position, from: buffer) else { return .notYetParsed }
            return .parsed(.integer(number))
        case dollar:
            return try parseBulkString(at: &position, from: buffer)
        case asterisk:
            return try parseArray(at: &position, from: buffer)
        default:
            throw "invalid token"
        }
    }

    private func parseArray(at position: inout Int, from buffer: ByteBuffer) throws -> PartialRedisData {
        guard let arraySize = try integer(at: &position, from: buffer) else { return .notYetParsed }
        guard arraySize > -1 else { return .parsed(.null) }

        var array = [PartialRedisData](repeating: .notYetParsed, count: arraySize)
        for index in 0..<arraySize {
            guard buffer.readableBytes - position > 0 else { return .notYetParsed }

            let parseResult = try parse(at: &position, from: buffer)
            switch parseResult {
            case .parsed:
                array[index] = parseResult
            default:
                return .notYetParsed
            }
        }

        let values = try array.map { partialRedisData -> RedisData in
            guard case .parsed(let value) = partialRedisData else {
                throw "Error!!!"
            }
            return value
        }

        return .parsed(.array(values))
    }

    private func parseSimpleString(at position: inout Int, from buffer: ByteBuffer) throws -> String? {
        //buffer.peekString
        let byteCount = buffer.readableBytes - position
        guard byteCount > 2 else { return nil } // terminatorToken guard to avoid bad access
        guard let bytes = buffer.peekBytes(at: position, length: byteCount) else { return nil }
        var offset = 0

        var carriageReturnFound = false

        // Loops until the carriagereturn
        detectionLoop: while offset < bytes.count {
            if bytes[offset] == carriageReturn {
                carriageReturnFound = true
                break detectionLoop
            }
            offset += 1
        }

        // Expects a carriage return
        guard carriageReturnFound else {
            return nil
        }

        // newline
        guard offset + 1 < bytes.count, bytes[offset + 1] == newline else {
            return nil
        }

        defer {
            // Move the pointer for recursive parsing...
            position += offset + 2
        }

        // Returns a String initialized with this data
        return String(bytes: bytes[..<offset], encoding: .utf8)
    }

    /// Parses an integer associated with the token at the provided position
    fileprivate func integer(at offset: inout Int, from input: ByteBuffer) throws -> Int? {
        // Parses a string
        guard let string = try parseSimpleString(at: &offset, from: input) else {
            return nil
        }

        guard let number = Int(string) else {
            throw "Unexpected"
        }
        return number
    }

    /// Parse a bulk string out
    fileprivate func parseBulkString(at position: inout Int, from buffer: ByteBuffer) throws -> PartialRedisData {
        guard let size = try integer(at: &position, from: buffer) else {
            return .notYetParsed
        }

        guard size > -1 else { return .parsed(.null) }
        guard buffer.readableBytes - position > (size + 1) else { return .notYetParsed }

        guard buffer.readableBytes > ("$\(size)\r\n".count + size + 2) else { return .notYetParsed }

        guard size > 0 else { // special case
            position += size + 2
            return .parsed(.bulkString(Data()))
        }

        let byteCount = buffer.readableBytes - position
        guard let bytes = buffer.peekBytes(at: position, length: byteCount) else { return .notYetParsed }

        defer { position += size + 2 }
        return .parsed(.bulkString(Data(bytes[..<size])))
    }
}

indirect enum PartialRedisData {
    case notYetParsed
    case parsed(RedisData)
}


extension ByteBuffer {
    internal func peekBytes(at skipping: Int = 0, length: Int) -> [UInt8]? {
        guard let bytes = getBytes(at: skipping + readerIndex, length: length) else { return nil }
        return bytes
    }
}
