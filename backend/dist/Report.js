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
var ReportCloseResultCode;
(function (ReportCloseResultCode) {
    ReportCloseResultCode[ReportCloseResultCode["Success"] = 0] = "Success";
    ReportCloseResultCode[ReportCloseResultCode["Exception1"] = -1] = "Exception1";
    ReportCloseResultCode[ReportCloseResultCode["Exception2"] = -2] = "Exception2";
    ReportCloseResultCode[ReportCloseResultCode["LogInsertFailed"] = -3] = "LogInsertFailed";
    ReportCloseResultCode[ReportCloseResultCode["UpdateFailed"] = -4] = "UpdateFailed";
    ReportCloseResultCode[ReportCloseResultCode["PermissionDenied"] = -5] = "PermissionDenied";
    ReportCloseResultCode[ReportCloseResultCode["DBConnFailed"] = -6] = "DBConnFailed";
})(ReportCloseResultCode || (ReportCloseResultCode = {}));
class ReportCloseResult {
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
class Report {
    constructor(id, title, description, severity, latitude, longitude, status, createdBy, createdAt, closedBy, closedAt) {
        this.id = id;
        this.title = title;
        this.description = description;
        this.severity = severity;
        this.longitude = longitude;
        this.latitude = latitude;
        this.status = status;
        this.createdBy = createdBy;
        this.createdAt = createdAt;
        this.closedBy = closedBy;
        this.closedAt = closedAt;
    }
    static getCached(id, conn) {
        return __awaiter(this, void 0, void 0, function* () {
            let report = Report.cached.get(id);
            if (report == undefined) {
                const row = yield conn.selectRow("select id,title,description,severity,status,latitude,longitude,createdBy,createdAt,closedBy,closedAt from tblReport where id=? limit 1;", [id]);
                if (row == null) {
                    Report.cached.set(id, null);
                    return null;
                }
                const title = row[1];
                const description = row[2];
                const severity = row[3];
                const status = row[4];
                const longitude = Number(row[5]);
                const latitude = Number(row[6]);
                const createdBy = Number(row[7]);
                const createdAt = new Date(row[8]);
                const closedBy = Number(row[9]);
                const closedAt = new Date(row[10]);
                report = new Report(id, title, description, severity, latitude, longitude, status, createdBy, createdAt, closedBy, closedAt);
                Report.cached.set(id, report);
            }
            return report;
        });
    }
    static create(title, description, severity, latitude, longitude, status, createdBy, createdAt, closedBy, closedAt, conn) {
        return __awaiter(this, void 0, void 0, function* () {
            try {
                if (status == null) {
                    status = "OPEN";
                }
                const insertId = yield conn.insert("insert into tblReport(title,description,severity,latitude,longitude,status,createdBy,createdAt,closedBy,closedAt)values(?,?,?,?,?,?,?,?,?,?);", [
                    title, description, severity,
                    latitude, longitude, status,
                    createdBy, createdAt,
                    closedBy, closedAt
                ]);
                if (insertId == null) {
                    return null;
                }
                const report = new Report(insertId, title, description, severity, latitude, longitude, status, createdBy, createdAt, closedBy, closedAt);
                Report.cached.set(insertId, report);
                return report;
            }
            catch (ex) {
                console.error(ex);
                return null;
            }
        });
    }
    static select(conn, status) {
        return __awaiter(this, void 0, void 0, function* () {
            const ids = [];
            try {
                let rows;
                if (status == null || status === "ALL") {
                    rows = yield conn.selectAll("select id from tblReport;", []);
                }
                else {
                    rows = yield conn.selectAll("select id from tblReport where status=?;", [status]);
                }
                for (const row of rows) {
                    ids.push(row["id"]);
                }
                return ids;
            }
            catch (ex) {
                console.error(ex);
                return null;
            }
            finally {
            }
        });
    }
    /*
    async hasPermission(updater:number,conn:DBConnection):Promise<boolean>{
        const hasPermission=await conn.selectSingle<number>(
            "select 1 from tblUser as u inner join tblAdmin as a on u.id=a.userId where u.id=? and u.status=1 limit 1;",
            [updater]
        );
        return hasPermission!=null;
    }
       */
    setStatus(status, closedBy, closedAt, conn) {
        return __awaiter(this, void 0, void 0, function* () {
            const changedCount = yield conn.update("update tblReport set status=?,closedBy=?,closedAt=? where id=? and status=? limit 1;", [status, closedBy, closedAt, this.id, this.status]);
            if (changedCount == 1) {
                this.status = status;
            }
            return changedCount;
        });
    }
    close(closedBy, conn) {
        return __awaiter(this, void 0, void 0, function* () {
            try {
                yield conn.beginTransaction();
                const closedAt = new Date();
                const changedCount = yield this.setStatus("CLOSED", closedBy, closedAt, conn);
                if (changedCount != 1) {
                    yield conn.rollback();
                    return new ReportCloseResult(ReportCloseResultCode.UpdateFailed);
                }
                yield conn.commit();
                this.status = "CLOSED";
                this.closedBy = closedBy;
                this.closedAt = closedAt;
                return new ReportCloseResult(ReportCloseResultCode.Success);
            }
            catch (ex1) {
                console.error(ex1);
                try {
                    yield conn.rollback();
                }
                catch (_a) { }
                return new ReportCloseResult(ReportCloseResultCode.Exception1);
            }
            finally {
            }
        });
    }
}
Report.cached = new Map();
exports.default = Report;
