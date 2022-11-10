//
//  ActionEvent.swift
//  PodDemo3
//
//  Created by KOYO on 2022/9/30.
//

import Foundation

struct ActionEvent {
    static let getRouterRtpCapabilities = "getRouterRtpCapabilities"
    static let createWebRtcTransport = "createWebRtcTransport"
    static let join = "join"
    static let produce = "produce"
    static let connectWebRtcTransport = "connectWebRtcTransport"//connectWebRtcTransport"
    
}


struct ActionEventID {
    static let kConnectID = 100000
    static let kCreateSendID = 100001
    static let kCreateRecvID = 100002
    static let kJoinID = 100003
    static let kProduce = 100004
    static let kConnectSendTransport = 100005
    static let kConnectRecvTransport = 100006
    
}

struct ARDEmu {
    static let kARDMediaStreamId = "ARDAMS"
    static let kARDAudioTrackId = "ARDAMSa0"
    static let kARDVideoTrackId = "ARDAMSv0"
}
