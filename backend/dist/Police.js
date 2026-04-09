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
const db_js_1 = require("./db.js");
const SQLHelper_js_1 = __importDefault(require("./SQLHelper.js"));
var RemovePoliceResultCode;
(function (RemovePoliceResultCode) {
    RemovePoliceResultCode[RemovePoliceResultCode["Success"] = 0] = "Success";
    RemovePoliceResultCode[RemovePoliceResultCode["Exception1"] = -1] = "Exception1";
    RemovePoliceResultCode[RemovePoliceResultCode["DBConnFailed"] = -3] = "DBConnFailed";
    RemovePoliceResultCode[RemovePoliceResultCode["UpdatePoliceFailed"] = -4] = "UpdatePoliceFailed";
})(RemovePoliceResultCode || (RemovePoliceResultCode = {}));
class RemovePoliceResult {
    constructor() {
        this.code = RemovePoliceResultCode.Success;
    }
    setCode(code) {
        this.code = code;
    }
}
var CreatePoliceResultCode;
(function (CreatePoliceResultCode) {
    CreatePoliceResultCode[CreatePoliceResultCode["Success"] = 0] = "Success";
    CreatePoliceResultCode[CreatePoliceResultCode["Exception1"] = -1] = "Exception1";
    CreatePoliceResultCode[CreatePoliceResultCode["DBConnFailed"] = -3] = "DBConnFailed";
    CreatePoliceResultCode[CreatePoliceResultCode["InsertPoliceFailed"] = -4] = "InsertPoliceFailed";
    CreatePoliceResultCode[CreatePoliceResultCode["AlreadyPolice"] = -5] = "AlreadyPolice";
})(CreatePoliceResultCode || (CreatePoliceResultCode = {}));
class CreatePoliceResult {
    constructor() {
        this.code = CreatePoliceResultCode.Success;
        this.policeId = -1;
    }
    setCode(code) {
        this.code = code;
    }
    setPoliceId(policeId) {
        this.policeId = policeId;
    }
}
class GetCurrentCaseIdResult {
    constructor() {
        this.code = 0;
        this.caseId = null;
    }
}
class GetPoliceIdResult {
    constructor() {
        this.code = 0;
        this.policeId = null;
    }
}
class Police {
    static getPoliceId(officerId) {
        return __awaiter(this, void 0, void 0, function* () {
            let conn = null;
            const result = new GetPoliceIdResult();
            try {
                conn = yield (0, db_js_1.getDbConnection)();
                const policeId = yield SQLHelper_js_1.default.selectSingle("select id from tblPolice where officerId=? limit 1;", conn, [officerId]);
                result.policeId = policeId;
                return result;
            }
            catch (err) {
                result.code = -1;
                return result;
            }
            finally {
                conn === null || conn === void 0 ? void 0 : conn.release();
            }
        });
    }
    static getCurrentCaseId(policeId) {
        return __awaiter(this, void 0, void 0, function* () {
            let conn = null;
            const result = new GetCurrentCaseIdResult();
            try {
                conn = yield (0, db_js_1.getDbConnection)();
                const caseId = yield SQLHelper_js_1.default.selectSingle("select caseId from tblPoliceCase where policeId=? limit 1;", conn, [policeId]);
                result.caseId = caseId;
                return result;
            }
            catch (err) {
                result.code = -1;
                return result;
            }
            finally {
                conn === null || conn === void 0 ? void 0 : conn.release();
            }
        });
    }
    static create(userId, officerId, createdBy) {
        return __awaiter(this, void 0, void 0, function* () {
            let conn = null;
            const result = new CreatePoliceResult();
            try {
                conn = yield (0, db_js_1.getDbConnection)();
                yield conn.beginTransaction();
                const policeId = yield SQLHelper_js_1.default.insert("insert into tblPolice(userId,officerId,createdBy)values(?,?,?);", conn, [userId, officerId, createdBy]);
                if (policeId == null) {
                    yield conn.rollback();
                    result.code = CreatePoliceResultCode.InsertPoliceFailed;
                    return result;
                }
                result.setPoliceId(policeId);
                yield conn.commit();
                return result;
            }
            catch (err) {
                try {
                    yield (conn === null || conn === void 0 ? void 0 : conn.rollback());
                }
                catch (_a) { }
                if ((err === null || err === void 0 ? void 0 : err.code) === "ER_DUP_ENTRY") {
                    result.code = CreatePoliceResultCode.AlreadyPolice;
                    return result;
                }
                result.code = CreatePoliceResultCode.Exception1;
                return result;
            }
            finally {
                conn === null || conn === void 0 ? void 0 : conn.release();
            }
        });
    }
    static remove(policeId, updatedBy) {
        return __awaiter(this, void 0, void 0, function* () {
            let conn = null;
            let sql;
            const result = new RemovePoliceResult();
            try {
                conn = yield (0, db_js_1.getDbConnection)();
                yield conn.beginTransaction();
                sql = "update tblPolice set isActive=0 where id=? and isActive=1;";
                const changedCount = yield SQLHelper_js_1.default.execute(sql, conn, [policeId]);
                if (changedCount !== 1) {
                    yield conn.rollback();
                    result.code = RemovePoliceResultCode.UpdatePoliceFailed;
                    return result;
                }
                yield conn.commit();
                return result;
            }
            catch (ex1) {
                try {
                    yield (conn === null || conn === void 0 ? void 0 : conn.rollback());
                }
                catch (_a) { }
                result.code = RemovePoliceResultCode.Exception1;
                return result;
            }
            finally {
                conn === null || conn === void 0 ? void 0 : conn.release();
            }
        });
    }
}
exports.default = Police;
