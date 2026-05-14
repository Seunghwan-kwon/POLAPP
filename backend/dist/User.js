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
}
class User {
    static remove(conn, userId, updatedBy) {
        return __awaiter(this, void 0, void 0, function* () {
            const result = new UserRemoveResult();
            try {
                yield conn.beginTransaction();
                const historyId = yield conn.insert("insert into tblUserHistory(userId,email,passwordHash)select id,email,passwordHash from tblUser where id=? limit 1;", [userId]);
                if (historyId == null) {
                    yield conn.rollback();
                    result.code = UserRemoveResultCode.HistoryInsertFailed;
                    return result;
                }
                const changedCount = yield conn.update("delete from tblUser where id=?;", [userId]);
                if (changedCount !== 1) {
                    yield conn.rollback();
                    result.code = UserRemoveResultCode.DeleteFailed;
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
                result.code = UserRemoveResultCode.Exception1;
                return result;
            }
            finally {
                conn === null || conn === void 0 ? void 0 : conn.release();
            }
        });
    }
    static login(conn, email, password) {
        return __awaiter(this, void 0, void 0, function* () {
            const result = new UserLoginResult();
            try {
                const userRow = yield conn.selectRow("select id,passwordHash from tblUser where email=? and isActive=1 limit 1;", [email]);
                if (userRow == null) {
                    yield conn.rollback();
                    result.code = UserLoginResultCode.NoSuchUser;
                    return result;
                }
                const passwordMatched = yield bcrypt_1.default.compare(password, userRow.passwordHash);
                if (!passwordMatched) {
                    yield conn.rollback();
                    result.code = UserLoginResultCode.PasswordMismatch;
                    return result;
                }
                const insertId = yield conn.insert("insert into tblLoginLog(userId,method)values(?,1);", [userRow.id]);
                if (insertId == null) {
                    yield conn.rollback();
                    result.code = UserLoginResultCode.LogInsertFailed;
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
                result.code = UserLoginResultCode.Exception1;
                return result;
            }
            finally {
                conn === null || conn === void 0 ? void 0 : conn.release();
            }
        });
    }
    static create(conn, email, password, createdBy, name) {
        return __awaiter(this, void 0, void 0, function* () {
            const result = new UserCreateResult();
            try {
                yield conn.beginTransaction();
                const passwordHash = yield bcrypt_1.default.hash(password, 12);
                const userId = yield conn.insert("insert into tblUser(email,passwordHash,createdBy)values(?,?,?);", [email, passwordHash, createdBy]);
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
                result.code = UserCreateResultCode.Exception1;
                return result;
            }
            finally {
                conn === null || conn === void 0 ? void 0 : conn.release();
            }
        });
    }
}
exports.default = User;
