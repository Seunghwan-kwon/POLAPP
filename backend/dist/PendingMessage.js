"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
class PendingMessage {
    constructor(sender, region, content, timestamp) {
        this.sender = sender;
        this.region = region;
        this.content = content;
        this.timestamp = timestamp;
    }
}
exports.default = PendingMessage;
