"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.getDBConnection = getDBConnection;
const Officer_js_1 = __importDefault(require("./Officer.js"));
const DBConnection_js_1 = __importDefault(require("./DBConnection.js"));
const Region_js_1 = __importDefault(require("./Region.js"));
const Role_js_1 = __importDefault(require("./Role.js"));
const MySqlConnection_js_1 = require("./MySqlConnection.js");
var DBType;
(function (DBType) {
    DBType[DBType["MySQL"] = 0] = "MySQL";
    DBType[DBType["Sqlite3"] = 1] = "Sqlite3";
})(DBType || (DBType = {}));
const dbType = DBType.MySQL;
function getDBConnection() {
    return __awaiter(this, void 0, void 0, function* () {
        if (dbType == DBType.MySQL) {
            const conn = yield (0, MySqlConnection_js_1.getMySqlConnection)();
            return conn;
        }
        else if (dbType == DBType.Sqlite3) {
            return new DBConnection_js_1.default();
        }
        else {
            return new DBConnection_js_1.default();
        }
    });
}
class AppServer {
    constructor() {
        this.updatedOfficers = new Map();
        this.officers = new Map();
        this.pendingMessages = new Array();
        this.adminRole = null;
    }
    getAdminRole() {
        return __awaiter(this, void 0, void 0, function* () {
            if (this.adminRole == null) {
                try {
                    const conn = yield getDBConnection();
                    const role = yield Role_js_1.default.findByCode("ADMIN", conn);
                    this.adminRole = role;
                }
                catch (ex) {
                    console.error(ex);
                    return null;
                }
            }
            return this.adminRole;
        });
    }
    syncOfficerLocations() {
        return __awaiter(this, void 0, void 0, function* () {
            const updatedOfficers = this.updatedOfficers.values();
            for (const officer of updatedOfficers) {
                const region = officer.region;
                if (region == null) {
                    continue;
                }
                let peers = region.officers.values();
                for (const peer of peers) {
                    if (peer == officer) {
                        continue;
                    }
                    peer.syncPeerLocation(officer);
                }
                const adminRole = yield this.getAdminRole();
                if (adminRole != null) {
                    peers = adminRole.officers.values();
                    for (const peer of peers) {
                        if (peer == officer) {
                            continue;
                        }
                        peer.syncPeerLocation(officer);
                    }
                }
            }
            this.updatedOfficers.clear();
        });
    }
    broadcastOfficerMessages() {
        for (const pendingMessage of this.pendingMessages) {
            const sender = pendingMessage.sender;
            const region = sender.region;
            if (region == null) {
                console.log("[broadcaseOfficerMessages] region==null");
                continue;
            }
            const peers = region.officers.values();
            for (const peer of peers) {
                if (peer == sender) {
                    continue;
                }
                peer.syncPeerMessage(pendingMessage);
            }
        }
        this.pendingMessages.length = 0;
    }
    setOfficerJoined(officerCode, regionCode, roleCode, socket) {
        return __awaiter(this, void 0, void 0, function* () {
            try {
                const conn = yield getDBConnection();
                const result = yield Officer_js_1.default.findByCode(conn, officerCode);
                if (result.code != 0) {
                    console.log(`[setOfficerJoined] result.code=${result.code}`);
                    return null;
                }
                const officer = result.officer;
                if (officer == null) {
                    console.log(`[setOfficerJoined] officer=null`);
                    return null;
                }
                const origOfficers = this.officers.values();
                for (const origOfficer of origOfficers) {
                    if (origOfficer == officer) {
                        continue;
                    }
                    officer.syncPeerLocation(origOfficer);
                }
                if (regionCode != null) {
                    const region = yield Region_js_1.default.findByCode(regionCode, conn);
                    if (region != null) {
                        officer.setRegion(region);
                    }
                }
                if (roleCode != null) {
                    const role = yield Role_js_1.default.findByCode(roleCode, conn);
                    if (role != null) {
                        officer.setRole(role);
                    }
                }
                officer.addSocket(socket);
                this.officers.set(officer.id, officer);
                return officer;
            }
            catch (e) {
                console.error(e);
                console.log(`[setOfficerJoined] exception=${e.toString()}`);
                return null;
            }
        });
    }
    loop() {
        return __awaiter(this, void 0, void 0, function* () {
            while (true) {
                yield this.syncOfficerLocations();
                this.broadcastOfficerMessages();
                yield new Promise(function (resolve) {
                    setTimeout(resolve, 50);
                });
            }
        });
    }
    pushPendingMessage(pendingMessage) {
        this.pendingMessages.push(pendingMessage);
        return pendingMessage;
    }
    setOfficerOffline(officer) {
        this.officers.delete(officer.id);
    }
    setOfficerLocationUpdated(officer) {
        this.updatedOfficers.set(officer.id, officer);
    }
}
exports.default = AppServer;
