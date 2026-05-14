"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
class PendingMessage {
    constructor(sender, content, timestamp) {
        this.sender = sender;
        this.content = content;
        this.timestamp = timestamp;
    }
}
exports.default = PendingMessage;
