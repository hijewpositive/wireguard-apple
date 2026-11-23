// SPDX-License-Identifier: MIT
// Copyright © 2026 WireGuard LLC. All Rights Reserved.

import Foundation

enum TunnelDetailRestoration {
    struct Node {
        let tunnelName: String?
        let children: [Node]

        init(tunnelName: String?, children: [Node]) {
            self.tunnelName = tunnelName
            self.children = children
        }
    }

    static func tunnelName(in navigationHierarchy: [Node]) -> String? {
        return navigationHierarchy.reversed().lazy.compactMap(tunnelName(in:)).first
    }

    private static func tunnelName(in node: Node) -> String? {
        if let nestedTunnelName = node.children.reversed().lazy.compactMap(tunnelName(in:)).first {
            return nestedTunnelName
        }
        return node.tunnelName
    }
}
