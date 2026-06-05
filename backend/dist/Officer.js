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
const Region_js_1 = __importDefault(require("./Region.js"));
const Utils_js_1 = require("./Utils.js");
var RemoveResultCode;
(function (RemoveResultCode) {
    RemoveResultCode[RemoveResultCode["Success"] = 0] = "Success";
    RemoveResultCode[RemoveResultCode["Exception1"] = -1] = "Exception1";
    RemoveResultCode[RemoveResultCode["DBConnFailed"] = -3] = "DBConnFailed";
    RemoveResultCode[RemoveResultCode["UpdateFailed"] = -4] = "UpdateFailed";
})(RemoveResultCode || (RemoveResultCode = {}));
class RemoveResult {
    constructor(code) {
        this.code = code;
    }
}
var CreateResultCode;
(function (CreateResultCode) {
    CreateResultCode[CreateResultCode["Success"] = 0] = "Success";
    CreateResultCode[CreateResultCode["Exception1"] = -1] = "Exception1";
    CreateResultCode[CreateResultCode["DBConnFailed"] = -3] = "DBConnFailed";
    CreateResultCode[CreateResultCode["InsertFailed"] = -4] = "InsertFailed";
    CreateResultCode[CreateResultCode["Duplicate"] = -5] = "Duplicate";
})(CreateResultCode || (CreateResultCode = {}));
class CreateResult {
    constructor(code, officer) {
        this.code = code;
        this.officer = officer;
    }
}
var FindResultCode;
(function (FindResultCode) {
    FindResultCode[FindResultCode["Success"] = 0] = "Success";
    FindResultCode[FindResultCode["Error"] = -1] = "Error";
})(FindResultCode || (FindResultCode = {}));
class FindResult {
    constructor(code, officer) {
        this.code = code;
        this.officer = officer;
    }
}
class Officer {
    constructor(id, code, name, rank, region, affiliation, appServer) {
        this.id = id;
        this.x = 0;
        this.y = 0;
        this.region = region;
        this.role = null;
        this.code = code;
        this.name = name;
        this.rank = rank;
        this.affiliation = affiliation;
        this.socket = null;
        this.initialLocationUpdate = true;
        this.appServer = appServer;
    }
    static getCached(id, conn, appServer) {
        return __awaiter(this, void 0, void 0, function* () {
            let officer = Officer.cached.get(id);
            if (officer === undefined) {
                const row = yield conn.selectRow("select id,code,name,rank,region,affiliation from tblOfficer where id=? limit 1;", [id]);
                if (row == null) {
                    Officer.cached.set(id, null);
                    return null;
                }
                const code = String(row[1]);
                const name = String(row[2]);
                const rank = String(row[3]);
                const regionId = Number(row[4]);
                const affiliation = String(row[5]);
                const region = yield Region_js_1.default.getCached(regionId, conn);
                officer = new Officer(id, code, name, rank, region, affiliation, appServer);
                Officer.cached.set(id, officer);
            }
            return officer;
        });
    }
    getMatchingCode(conn) {
        return __awaiter(this, void 0, void 0, function* () {
            const matchingCode = yield conn.selectSingle("select matchingCode from tblOfficer where id=? limit 1;", [this.id]);
            return matchingCode;
        });
    }
    static findByCode(conn, code, appServer) {
        return __awaiter(this, void 0, void 0, function* () {
            const id = yield conn.selectSingle("select id from tblOfficer where code=? limit 1;", [code]);
            if (id == null) {
                return null;
            }
            const officer = yield Officer.getCached(id, conn, appServer);
            if (!officer) {
                return null;
            }
            return officer;
        });
    }
    static create(conn, id, code, name, rank, region, affiliation, createdBy, appServer) {
        return __awaiter(this, void 0, void 0, function* () {
            try {
                yield conn.beginTransaction();
                const regionId = region == null ? 0 : region.id;
                const insertId = yield conn.insert("insert into tblOfficer(userId,officerId,name,rank,region,affiliation,createdBy)values(?,?,?,?,?,?,?);", [
                    id, code, name, rank,
                    regionId, affiliation,
                    createdBy
                ]);
                if (insertId == null) {
                    yield conn.rollback();
                    return new CreateResult(CreateResultCode.InsertFailed, null);
                }
                yield conn.commit();
                const officer = new Officer(insertId, code, name, rank, region, affiliation, appServer);
                Officer.cached.set(officer.id, officer);
                return new CreateResult(0, officer);
            }
            catch (err) {
                try {
                    yield (conn === null || conn === void 0 ? void 0 : conn.rollback());
                }
                catch (_a) { }
                if ((err === null || err === void 0 ? void 0 : err.code) === "ER_DUP_ENTRY") {
                    return new CreateResult(CreateResultCode.Duplicate, null);
                }
                return new CreateResult(CreateResultCode.Exception1, null);
            }
            finally {
            }
        });
    }
    remove(updatedBy, conn) {
        return __awaiter(this, void 0, void 0, function* () {
            try {
                yield conn.beginTransaction();
                const changedCount = yield conn.update("update tblOfficer set isActive=0 where id=? and isActive=1 limit 1;", [this.id]);
                if (changedCount !== 1) {
                    yield conn.rollback();
                    return new RemoveResult(RemoveResultCode.UpdateFailed);
                }
                yield conn.commit();
                return new RemoveResult(RemoveResultCode.Success);
            }
            catch (ex1) {
                try {
                    yield conn.rollback();
                }
                catch (_a) { }
                return new RemoveResult(RemoveResultCode.Exception1);
            }
        });
    }
    setSocket(socket) {
        if (this.socket) {
            this.socket.disconnect();
            this.socket = null;
        }
        this.socket = socket;
        console.log(`[${(0, Utils_js_1.getDateStr)()}] [setSocket] officer.code=${this.code} socket.id=${socket.id}`);
    }
    removeSocket(socket) {
        if (this.socket != socket) {
            return;
        }
        this.socket = null;
        this.appServer.setOfficerOffline(this);
        if (this.region) {
            this.region.removeOfficer(this);
        }
        if (this.role) {
            this.role.removeOfficer(this);
        }
        this.initialLocationUpdate = true;
    }
    emit(name, arg) {
        if (this.socket == null) {
            return 0;
        }
        this.socket.emit(name, arg);
        return 1;
    }
    notifyPeerOffline(peer) {
        const payload = {
            officerId: peer.code,
        };
        if (this.socket == null) {
            return 0;
        }
        this.socket.emit("removeColleagueLocation", payload);
        return 1;
    }
    syncPeerLocation(peer) {
        const region = peer.region;
        if (region == null) {
            return -1;
        }
        if (this.socket == null) {
            return -2;
        }
        const payload = /*peer.initialLocationUpdate?*/ {
            officerId: peer.code,
            region: region.code,
            latitude: peer.x,
            longitude: peer.y,
            name: peer.name,
            rank: peer.rank,
            affiliation: peer.affiliation
        };
        /*:{
            officerId:peer.code,
            region:region.code,
            latitude:peer.x,
            longitude:peer.y
        };*/
        this.socket.emit("updateColleagueLocation", payload);
        return 1;
    }
    syncPeerMessage(message) {
        if (this.socket == null) {
            return -1;
        }
        const peer = message.sender;
        const region = message.region;
        let regionCode;
        if (region == null) {
            regionCode = "ALL";
        }
        else {
            regionCode = region.code;
        }
        const payload = {
            officerId: peer.code,
            region: regionCode,
            message: message.content,
            timestamp: message.timestamp
        };
        this.socket.emit("receiveRadioMessage", payload);
        return 1;
    }
    setRole(role) {
        if (this.role != null) {
            if (this.role == role) {
                return 1;
            }
            else {
                this.role.removeOfficer(this);
            }
        }
        role.addOfficer(this);
        this.role = role;
        console.log(`[${(0, Utils_js_1.getDateStr)()}] [Officer.setRole] officer.code=${this.code} role.code=${role.code}`);
        return 0;
    }
    setRegion() {
        if (this.region == null) {
            console.log(`[${(0, Utils_js_1.getDateStr)()}] [Officer.setRegion] this.region=null`);
            return -1;
        }
        this.region.addOfficer(this);
        console.log(`[${(0, Utils_js_1.getDateStr)()}] [Officer.setRegion] officer.code=${this.code} region.code=${this.region.code}`);
        return 0;
    }
    setLocation(x, y) {
        this.x = x;
        this.y = y;
    }
}
Officer.cached = new Map();
exports.default = Officer;
