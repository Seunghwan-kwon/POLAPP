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
const bcrypt_1 = __importDefault(require("bcrypt"));
const db_js_1 = require("./db.js");
const SQLHelper_js_1 = __importDefault(require("./SQLHelper.js"));
var UserCreateResultCode;
(function (UserCreateResultCode) {
    UserCreateResultCode[UserCreateResultCode["Success"] = 0] = "Success";
    UserCreateResultCode[UserCreateResultCode["Exception1"] = -1] = "Exception1";
    UserCreateResultCode[UserCreateResultCode["Exception2"] = -2] = "Exception2";
    UserCreateResultCode[UserCreateResultCode["DBConnFailed"] = -3] = "DBConnFailed";
})(UserCreateResultCode || (UserCreateResultCode = {}));
class UserCreateResult {
    constructor() {
        this.code = UserCreateResultCode.Success;
        this.userId = null;
    }
    setCode(code) {
        this.code = code;
    }
}
var UserLoginResultCode;
(function (UserLoginResultCode) {
    UserLoginResultCode[UserLoginResultCode["Success"] = 0] = "Success";
    UserLoginResultCode[UserLoginResultCode["Exception1"] = -1] = "Exception1";
    UserLoginResultCode[UserLoginResultCode["Exception2"] = -2] = "Exception2";
    UserLoginResultCode[UserLoginResultCode["DBConnFailed"] = -3] = "DBConnFailed";
    UserLoginResultCode[UserLoginResultCode["PasswordMismatch"] = -4] = "PasswordMismatch";
    UserLoginResultCode[UserLoginResultCode["LogInsertFailed"] = -5] = "LogInsertFailed";
    UserLoginResultCode[UserLoginResultCode["NoSuchUser"] = -6] = "NoSuchUser";
})(UserLoginResultCode || (UserLoginResultCode = {}));
class UserLoginResult {
    constructor() {
        this.code = UserLoginResultCode.Success;
        this.userId = null;
    }
    setCode(code) {
        this.code = code;
    }
}
var UserRemoveResultCode;
(function (UserRemoveResultCode) {
    UserRemoveResultCode[UserRemoveResultCode["Success"] = 0] = "Success";
    UserRemoveResultCode[UserRemoveResultCode["Exception1"] = -1] = "Exception1";
    UserRemoveResultCode[UserRemoveResultCode["HistoryInsertFailed"] = -2] = "HistoryInsertFailed";
    UserRemoveResultCode[UserRemoveResultCode["DeleteFailed"] = -3] = "DeleteFailed";
})(UserRemoveResultCode || (UserRemoveResultCode = {}));
class UserRemoveResult {
    constructor() {
        this.code = UserRemoveResultCode.Success;
    }
    setCode(code) {
        this.code = code;
    }
}
class User {
    static remove(userId, updatedBy) {
        return __awaiter(this, void 0, void 0, function* () {
            let conn = null;
            const result = new UserRemoveResult();
            try {
                conn = yield (0, db_js_1.getDbConnection)();
                yield conn.beginTransaction();
                const historyId = yield SQLHelper_js_1.default.insert("insert into tblUserHistory(userId,email,passwordHash)select id,email,passwordHash from tblUser where id=? limit 1;", conn, [userId]);
                if (historyId == null) {
                    yield conn.rollback();
                    result.setCode(UserRemoveResultCode.HistoryInsertFailed);
                    return result;
                }
                const changedCount = yield SQLHelper_js_1.default.execute("delete from tblUser where id=?;", conn, [userId]);
                if (changedCount !== 1) {
                    yield conn.rollback();
                    result.setCode(UserRemoveResultCode.DeleteFailed);
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
                result.setCode(UserRemoveResultCode.Exception1);
                return result;
            }
            finally {
                conn === null || conn === void 0 ? void 0 : conn.release();
            }
        });
    }
    static login(email, password) {
        return __awaiter(this, void 0, void 0, function* () {
            let conn = null;
            let sql;
            let result = new UserLoginResult();
            try {
                conn = yield (0, db_js_1.getDbConnection)();
                sql = "select id,passwordHash from tblUser where email=? and isActive=1 limit 1;";
                const userRow = yield SQLHelper_js_1.default.selectRow(sql, conn, [email]);
                if (userRow == null) {
                    yield conn.rollback();
                    result.setCode(UserLoginResultCode.NoSuchUser);
                    return result;
                }
                const passwordMatched = yield bcrypt_1.default.compare(password, userRow.passwordHash);
                if (!passwordMatched) {
                    yield conn.rollback();
                    result.setCode(UserLoginResultCode.PasswordMismatch);
                    return result;
                }
                sql = "insert into tblLoginLog(userId,method)values(?,1);";
                const insertId = yield SQLHelper_js_1.default.insert(sql, conn, [userRow.id]);
                if (insertId == null) {
                    yield conn.rollback();
                    result.setCode(UserLoginResultCode.LogInsertFailed);
                    return result;
                }
                result.userId = userRow.id;
                yield conn.commit();
                return result;
            }
            catch (ex1) {
                try {
                    yield (conn === null || conn === void 0 ? void 0 : conn.rollback());
                }
                catch (_a) { }
                result.setCode(UserLoginResultCode.Exception1);
                return result;
            }
            finally {
                conn === null || conn === void 0 ? void 0 : conn.release();
            }
        });
    }
    static create(email, password, createdBy, name) {
        return __awaiter(this, void 0, void 0, function* () {
            const result = new UserCreateResult();
            let conn = null;
            let sql;
            try {
                conn = yield (0, db_js_1.getDbConnection)();
                yield conn.beginTransaction();
                const passwordHash = yield bcrypt_1.default.hash(password, 12);
                sql = "insert into tblUser(email,passwordHash,createdBy)values(?,?,?);";
                const userId = yield SQLHelper_js_1.default.insert(sql, conn, [email, passwordHash, createdBy]);
                if (userId == null) {
                    yield conn.rollback();
                    return result;
                }
                result.userId = userId;
                yield conn.commit();
                return result;
            }
            catch (ex1) {
                try {
                    yield (conn === null || conn === void 0 ? void 0 : conn.rollback());
                }
                catch (_a) { }
                result.setCode(UserCreateResultCode.Exception1);
                return result;
            }
            finally {
                conn === null || conn === void 0 ? void 0 : conn.release();
            }
        });
    }
}
exports.default = User;
