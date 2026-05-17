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
Object.defineProperty(exports, "__esModule", { value: true });
exports.GetOfficerIdsResultCode = void 0;
var CaseSetCompleteResultCode;
(function (CaseSetCompleteResultCode) {
    CaseSetCompleteResultCode[CaseSetCompleteResultCode["Success"] = 0] = "Success";
    CaseSetCompleteResultCode[CaseSetCompleteResultCode["Exception1"] = -1] = "Exception1";
    CaseSetCompleteResultCode[CaseSetCompleteResultCode["Exception2"] = -2] = "Exception2";
    CaseSetCompleteResultCode[CaseSetCompleteResultCode["LogInsertFailed"] = -3] = "LogInsertFailed";
    CaseSetCompleteResultCode[CaseSetCompleteResultCode["UpdateFailed"] = -4] = "UpdateFailed";
    CaseSetCompleteResultCode[CaseSetCompleteResultCode["PermissionDenied"] = -5] = "PermissionDenied";
    CaseSetCompleteResultCode[CaseSetCompleteResultCode["DBConnFailed"] = -6] = "DBConnFailed";
})(CaseSetCompleteResultCode || (CaseSetCompleteResultCode = {}));
class CaseSetCompleteResult {
    constructor(code, logId) {
        this.code = code;
        this.logId = logId;
    }
}
var AssignOfficerResultCode;
(function (AssignOfficerResultCode) {
    AssignOfficerResultCode[AssignOfficerResultCode["Success"] = 0] = "Success";
    AssignOfficerResultCode[AssignOfficerResultCode["Exception1"] = -1] = "Exception1";
    AssignOfficerResultCode[AssignOfficerResultCode["InsertFailed"] = -2] = "InsertFailed";
})(AssignOfficerResultCode || (AssignOfficerResultCode = {}));
class AssignOfficerResult {
    constructor(code) {
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
    constructor(id) {
        this.id = id;
        this.state = -1;
    }
    static getCached(id, conn) {
        return __awaiter(this, void 0, void 0, function* () {
            let _case = Case.cached.get(id);
            if (_case === undefined) {
                const row = yield conn.selectRow("select id from tblCase where caseId=? limit 1;", [id]);
                if (row == null) {
                    Case.cached.set(id, null);
                    return null;
                }
                _case = new Case(id);
                Case.cached.set(id, _case);
            }
            return _case;
        });
    }
    static create(name, createdBy, conn) {
        return __awaiter(this, void 0, void 0, function* () {
            try {
                const insertId = yield conn.insert("insert into tblCase(name,createdBy)values(?,?);", [name, createdBy]);
                if (insertId == null) {
                    return null;
                }
                const _case = new Case(insertId);
                Case.cached.set(insertId, _case);
                return _case;
            }
            catch (ex) {
                console.error(ex);
                return null;
            }
        });
    }
    static getOfficerIds(conn, caseId) {
        return __awaiter(this, void 0, void 0, function* () {
            const result = new GetOfficerIdsResult();
            try {
                const rows = yield conn.selectAll("select id from tblCaseOfficer where caseId=?;", [caseId]);
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
            }
        });
    }
    assignOfficer(officerId, updatedBy, conn) {
        return __awaiter(this, void 0, void 0, function* () {
            try {
                const insertId = yield conn.insert("insert into tblCaseOfficer(caseId,policeId,updatedBy)values(?,?,?);", [this.id, officerId, updatedBy]);
                if (insertId == null) {
                    return new AssignOfficerResult(AssignOfficerResultCode.InsertFailed);
                }
                return new AssignOfficerResult(AssignOfficerResultCode.Success);
            }
            catch (ex) {
                return new AssignOfficerResult(AssignOfficerResultCode.Exception1);
            }
            finally {
            }
        });
    }
    setIncomplete(updatedBy) {
        return __awaiter(this, void 0, void 0, function* () {
        });
    }
    hasPermission(updater, conn) {
        return __awaiter(this, void 0, void 0, function* () {
            const hasPermission = yield conn.selectSingle("select 1 from tblUser as u inner join tblAdmin as a on u.id=a.userId where u.id=? and u.status=1 limit 1;", [updater]);
            return hasPermission != null;
        });
    }
    setState(state, conn) {
        return __awaiter(this, void 0, void 0, function* () {
            const changedCount = yield conn.update("update tblCase set state=? where id=? and state=?;", [state, this.id, this.state]);
            return changedCount;
        });
    }
    setComplete(updatedBy, conn) {
        return __awaiter(this, void 0, void 0, function* () {
            try {
                yield conn.beginTransaction();
                const hasPermission = yield conn.selectSingle("select 1 from tblUser as u inner join tblAdmin as a on u.id=a.userId where u.id=? and u.status=1 limit 1;", [updatedBy]);
                if (!(yield this.hasPermission(updatedBy, conn))) {
                    yield conn.rollback();
                    return new CaseSetCompleteResult(CaseSetCompleteResultCode.PermissionDenied, -1);
                }
                const changedCount = yield this.setState(200, conn);
                if (changedCount != 1) {
                    yield conn.rollback();
                    return new CaseSetCompleteResult(CaseSetCompleteResultCode.UpdateFailed, -1);
                }
                const logId = yield conn.insert("insert tblCaseLog(caseId,updatedBy)values(?,?);", [this.id, updatedBy]);
                if (logId == null) {
                    yield conn.rollback();
                    return new CaseSetCompleteResult(CaseSetCompleteResultCode.LogInsertFailed, -1);
                }
                yield conn.commit();
                return new CaseSetCompleteResult(CaseSetCompleteResultCode.LogInsertFailed, logId);
            }
            catch (ex1) {
                try {
                    yield conn.rollback();
                }
                catch (_a) { }
                return new CaseSetCompleteResult(CaseSetCompleteResultCode.Exception1, -1);
            }
            finally {
            }
        });
    }
}
Case.cached = new Map();
exports.default = Case;
