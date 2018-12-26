import Foundation
import NIO

public final class Redis: ChannelDuplexHandler {

    public typealias InboundIn = RedisData
    public typealias OutboundIn = RedisData
    public typealias OutboundOut = [RedisData]

    let eventLoop: EventLoop
    let channel: Channel

    var queued = 0
    var incommingResponses: [RedisData] = []
    var yeild: (([RedisData]) -> ())?

    init(_ eventLoop: EventLoop, channel: Channel) {
        self.channel = channel
        self.eventLoop = eventLoop
    }

    public static func connect(eventLoop: EventLoop) -> EventLoopFuture<Redis> {
        let bootstrap = ClientBootstrap(group: eventLoop)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                return channel.pipeline.add(handler: Encoder()).then {
                    return channel.pipeline.add(handler: Decoder())
                }
        }
        return bootstrap.connect(host: "127.0.0.1", port: 6379).then { channel in
            let redis = Redis(eventLoop, channel: channel)
            return channel.pipeline.add(handler: redis).map {
                return redis
            }
        }
    }

    public func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        let input = unwrapInboundIn(data)
        incommingResponses.append(input)
        queued -= 1
        if queued == 0 {
            yeild?(incommingResponses)
            incommingResponses.removeAll()
        }
    }


    public func send(message: RedisData) -> EventLoopFuture<()> {
        defer {
            channel.flush()
        }
        return channel.write(wrapOutboundOut([message]))
    }

    public func pipeLine(message: [RedisData]) -> EventLoopFuture<[RedisData]> {
        defer {
            channel.flush()
        }
        queued = message.count
        incommingResponses.reserveCapacity(message.count)
        _ = channel.write(wrapOutboundOut(message))
        let promise: EventLoopPromise<[RedisData]> = channel.eventLoop.newPromise()
        yeild = { messages in
            promise.succeed(result: messages)
        }
        return promise.futureResult
    }

    public func pipeLineStream(message: (StreamState) -> ()) {
        
    }

}

public enum StreamState {
    case message(RedisData)
    case done
}

public indirect enum RedisData {
    case null
    case basicString(String)
    case bulkString(Data)
    case error(String)
    case integer(Int)
    case array([RedisData])
}

final class Encoder: MessageToByteEncoder {

    typealias OutboundIn = [RedisData]

    func encode(ctx: ChannelHandlerContext, data: Encoder.OutboundIn, out: inout ByteBuffer) throws {
         let encoded = data.map(encode).joined()
         out.write(string: encoded)
    }
    
    private func encode(data: RedisData) -> String {
        switch data {
        case let .basicString(basicString):
            return "+\(basicString)\r\n"
        case let .error(err):
            return "-\(err)\r\n"
        case let .integer(integer):
            return ":\(integer)\r\n"
        case let .bulkString(bulkData):
            let str = String(bytes: bulkData, encoding: .utf8)!
            return "$\(bulkData.count.description)\r\n" + str + "\r\n"
        case .null:
            return "$-1\r\n"
        case let .array(array):
            let dataEncodedArray = array.map(encode(data:)).joined()
            return "*\(array.count)\r\n" + dataEncodedArray
        }
    }

}
