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
exports.GetOfficerIdsResultCode = void 0;
const db_js_1 = require("./db.js");
const SQLHelper_js_1 = __importDefault(require("./SQLHelper.js"));
var CaseSetCompleteResultCode;
(function (CaseSetCompleteResultCode) {
    CaseSetCompleteResultCode[CaseSetCompleteResultCode["Success"] = 0] = "Success";
    CaseSetCompleteResultCode[CaseSetCompleteResultCode["Exception1"] = -1] = "Exception1";
    CaseSetCompleteResultCode[CaseSetCompleteResultCode["Exception2"] = -2] = "Exception2";
    CaseSetCompleteResultCode[CaseSetCompleteResultCode["LogInsertFailed"] = -3] = "LogInsertFailed";
    CaseSetCompleteResultCode[CaseSetCompleteResultCode["CaseUpdateFailed"] = -4] = "CaseUpdateFailed";
    CaseSetCompleteResultCode[CaseSetCompleteResultCode["PermissionDenied"] = -5] = "PermissionDenied";
    CaseSetCompleteResultCode[CaseSetCompleteResultCode["DBConnFailed"] = -6] = "DBConnFailed";
})(CaseSetCompleteResultCode || (CaseSetCompleteResultCode = {}));
class CaseSetCompleteResult {
    constructor() {
        this.code = CaseSetCompleteResultCode.Success;
        this.logId = -1;
    }
    setCode(code) {
        this.code = code;
    }
    setLogId(logId) {
        this.logId = logId;
    }
}
var AssignPoliceResultCode;
(function (AssignPoliceResultCode) {
    AssignPoliceResultCode[AssignPoliceResultCode["Success"] = 0] = "Success";
    AssignPoliceResultCode[AssignPoliceResultCode["Exception1"] = -1] = "Exception1";
    AssignPoliceResultCode[AssignPoliceResultCode["InsertFailed"] = -2] = "InsertFailed";
})(AssignPoliceResultCode || (AssignPoliceResultCode = {}));
class AssignPoliceResult {
    constructor() {
        this.code = AssignPoliceResultCode.Success;
    }
    setCode(code) {
        this.code = code;
    }
}
var GetOfficerIdsResultCode;
(function (GetOfficerIdsResultCode) {
    GetOfficerIdsResultCode[GetOfficerIdsResultCode["Success"] = 0] = "Success";
    GetOfficerIdsResultCode[GetOfficerIdsResultCode["Exception1"] = -1] = "Exception1";
})(GetOfficerIdsResultCode || (exports.GetOfficerIdsResultCode = GetOfficerIdsResultCode = {}));
class GetOfficerIdsResult {
    constructor() {
        this.ids = new Array();
        this.code = GetOfficerIdsResultCode.Success;
    }
}
class Case {
    static create(createdBy) {
        return __awaiter(this, void 0, void 0, function* () {
        });
    }
    static getOfficerIds(caseId) {
        return __awaiter(this, void 0, void 0, function* () {
            let conn = null;
            let sql;
            let result = new GetOfficerIdsResult();
            try {
                conn = yield (0, db_js_1.getDbConnection)();
                const rows = yield SQLHelper_js_1.default.selectAll("select id from tblCasePolice where caseId=?;", conn, [caseId]);
                for (const row of rows) {
                    result.ids.push(row["id"]);
                }
                return result;
            }
            catch (ex) {
                result.code = GetOfficerIdsResultCode.Exception1;
                return result;
            }
            finally {
                if (conn != null) {
                    conn.release();
                }
            }
        });
    }
    static assignPolice(caseId, policeId, updatedBy) {
        return __awaiter(this, void 0, void 0, function* () {
            let conn = null;
            let sql;
            let result = new AssignPoliceResult();
            try {
                conn = yield (0, db_js_1.getDbConnection)();
                sql = "insert into tblCasePolice(caseId,policeId,updatedBy)values(?,?,?);";
                const affectedCount = yield SQLHelper_js_1.default.execute(sql, conn, [caseId, policeId, updatedBy]);
                if (affectedCount != 1) {
                    result.setCode(AssignPoliceResultCode.InsertFailed);
                    return result;
                }
                return result;
            }
            catch (ex) {
                result.setCode(AssignPoliceResultCode.Exception1);
                return result;
            }
            finally {
                if (conn != null) {
                    conn.release();
                }
            }
        });
    }
    static setIncomplete(caseId, updatedBy) {
        return __awaiter(this, void 0, void 0, function* () {
        });
    }
    static setComplete(caseId, updatedBy) {
        return __awaiter(this, void 0, void 0, function* () {
            let conn = null;
            let sql;
            let result = new CaseSetCompleteResult();
            try {
                conn = yield (0, db_js_1.getDbConnection)();
                sql = "select 1 from tblUser as u inner join tblAdmin as a on u.id=a.userId where u.id=? and u.status=1 limit 1;";
                const hasPermission = yield SQLHelper_js_1.default.selectSingle(sql, conn, [updatedBy]);
                if (hasPermission == null) {
                    yield conn.rollback();
                    result.setCode(CaseSetCompleteResultCode.PermissionDenied);
                    return result;
                }
                sql = "update tblCase set state=200 where id=? and state=0;";
                let affectedCount;
                affectedCount = yield SQLHelper_js_1.default.execute(sql, conn, [caseId]);
                if (affectedCount != 1) {
                    yield conn.rollback();
                    result.setCode(CaseSetCompleteResultCode.CaseUpdateFailed);
                    return result;
                }
                sql = "insert tblCaseLog(caseId,updatedBy)values(?,?);";
                const logId = yield SQLHelper_js_1.default.insert(sql, conn, [caseId, updatedBy]);
                if (logId == null) {
                    yield conn.rollback();
                    result.setCode(CaseSetCompleteResultCode.LogInsertFailed);
                    return result;
                }
                yield conn.commit();
                result.setLogId(logId);
                return result;
            }
            catch (ex1) {
                if (conn != null) {
                    try {
                        yield conn.rollback();
                        result.setCode(CaseSetCompleteResultCode.Exception1);
                        return result;
                    }
                    catch (ex2) {
                        result.setCode(CaseSetCompleteResultCode.Exception2);
                        return result;
                    }
                }
                else {
                    result.setCode(CaseSetCompleteResultCode.DBConnFailed);
                    return result;
                }
            }
            finally {
                if (conn != null) {
                    conn.release();
                }
            }
        });
    }
}
exports.default = Case;
