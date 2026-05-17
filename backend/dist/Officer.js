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
const Case_js_1 = __importDefault(require("./Case.js"));
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
var GetCaseResultCode;
(function (GetCaseResultCode) {
    GetCaseResultCode[GetCaseResultCode["Success"] = 0] = "Success";
    GetCaseResultCode[GetCaseResultCode["Error"] = -1] = "Error";
})(GetCaseResultCode || (GetCaseResultCode = {}));
class GetCaseResult {
    constructor(code, _case) {
        this.code = code;
        this._case = _case;
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
    constructor(id, conn, appServer) {
        this.id = id;
        this.x = 0;
        this.y = 0;
        this.region = null;
        this.role = null;
        this.code = "(unknown)";
        this.sockets = new Map();
        this.conn = conn;
        this.appServer = appServer;
    }
    static getCached(id, conn, appServer) {
        return __awaiter(this, void 0, void 0, function* () {
            let officer = Officer.cached.get(id);
            if (officer === undefined) {
                const row = yield conn.selectRow("select id from tblOfficer where id=? limit 1;", [id]);
                if (row == null) {
                    Officer.cached.set(id, null);
                    return null;
                }
                officer = new Officer(id, conn, appServer);
                Officer.cached.set(id, officer);
            }
            return officer;
        });
    }
    getMatchingCode() {
        return __awaiter(this, void 0, void 0, function* () {
            const matchingCode = yield this.conn.selectSingle("select matchingCode from tblOfficer where id=? limit 1;", [this.id]);
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
            officer.code = code;
            return officer;
        });
    }
    getCase() {
        return __awaiter(this, void 0, void 0, function* () {
            try {
                const caseId = yield this.conn.selectSingle("select caseId from tblOfficerCase where officerId=? limit 1;", [this.id]);
                if (caseId == null) {
                    return new GetCaseResult(GetCaseResultCode.Success, null);
                }
                const _case = yield Case_js_1.default.getCached(caseId, this.conn);
                return new GetCaseResult(GetCaseResultCode.Success, _case);
            }
            catch (err) {
                return new GetCaseResult(GetCaseResultCode.Error, null);
            }
            finally {
            }
        });
    }
    static create(conn, id, code, createdBy, appServer) {
        return __awaiter(this, void 0, void 0, function* () {
            try {
                yield conn.beginTransaction();
                const insertId = yield conn.insert("insert into tblOfficer(userId,officerId,createdBy)values(?,?,?);", [id, code, createdBy]);
                if (insertId == null) {
                    yield conn.rollback();
                    return new CreateResult(CreateResultCode.InsertFailed, null);
                }
                yield conn.commit();
                const officer = new Officer(insertId, conn, appServer);
                officer.code = code;
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
    remove(updatedBy) {
        return __awaiter(this, void 0, void 0, function* () {
            var _a;
            try {
                yield this.conn.beginTransaction();
                const changedCount = yield this.conn.update("update tblOfficer set isActive=0 where id=? and isActive=1 limit 1;", [this.id]);
                if (changedCount !== 1) {
                    yield this.conn.rollback();
                    return new RemoveResult(RemoveResultCode.UpdateFailed);
                }
                yield this.conn.commit();
                return new RemoveResult(RemoveResultCode.Success);
            }
            catch (ex1) {
                try {
                    yield ((_a = this.conn) === null || _a === void 0 ? void 0 : _a.rollback());
                }
                catch (_b) { }
                return new RemoveResult(RemoveResultCode.Exception1);
            }
            finally {
            }
        });
    }
    isOffline() {
        return this.sockets.size == 0;
    }
    addSocket(socket) {
        this.sockets.set(socket.id, socket);
    }
    removeSocket(socket) {
        this.sockets.delete(socket.id);
        if (this.isOffline()) {
            this.appServer.setOfficerOffline(this);
            if (this.region) {
                this.region.removeOfficer(this);
                this.region = null;
            }
            if (this.role) {
                this.role.removeOfficer(this);
                this.role = null;
            }
        }
    }
    notifyPeerOffline(peer) {
        const payload = {
            officerId: peer.code,
        };
        let result = 0;
        for (const socket of this.sockets.values()) {
            socket.emit("removeColleagueLocation", payload);
            result++;
        }
        return result;
    }
    syncPeerLocation(peer) {
        const region = peer.region;
        if (region == null) {
            return -1;
        }
        const payload = {
            officerId: peer.code,
            region: region.code,
            latitude: peer.x,
            longitude: peer.y
        };
        let result = 0;
        for (const socket of this.sockets.values()) {
            socket.emit("updateColleagueLocation", payload);
            result++;
        }
        return result;
    }
    syncPeerMessage(message) {
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
        let result = 0;
        for (const socket of this.sockets.values()) {
            socket.emit("receiveRadioMessage", payload);
            result++;
        }
        return result;
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
        console.log(`[Officer.setRole] officer.code=${this.code} role.code=${role.code}`);
        return 0;
    }
    setRegion(region) {
        if (this.region != null) {
            if (this.region == region) {
                return 1;
            }
            else {
                this.region.removeOfficer(this);
            }
        }
        region.addOfficer(this);
        this.region = region;
        console.log(`[Officer.setRegion] officer.code=${this.code} region.code=${region.code}`);
        return 0;
    }
    updateLocation(x, y) {
        this.x = x;
        this.y = y;
    }
}
Officer.cached = new Map();
exports.default = Officer;
