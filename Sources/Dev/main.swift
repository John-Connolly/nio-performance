//
//  main.swift
//  redis
//
//  Created by John Connolly on 2018-07-06.
//

import Foundation
import redis
import NIO



let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
let eventloop = group.next()

let redis = Redis.connect(eventLoop: eventloop).map { redis in

    let command = "SET".data(using: .utf8)!
    let key = "foo".data(using: .utf8)!
    let data = "bar".data(using: .utf8)!
    var message: [RedisData] = []
    for _ in 1...1_000_000 {
        message.append(RedisData.array([.bulkString(command),.bulkString(key),.bulkString(data)]))
    }

    let time = Date()
    redis.pipeLine(message: message).whenSuccess { resp in
        //print(resp)
        print(Date().timeIntervalSince(time))
        // version 1.8 takes 7.628605961799622 seconds in release mode for me
        // version 1.9 takes 41.16486203670502 seconds in release mode for me
    }
}




RunLoop.main.run()
