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
exports.MySqlConnection = void 0;
exports.getMySqlConnection = getMySqlConnection;
const DBConnection_js_1 = __importDefault(require("./DBConnection.js"));
const promise_1 = __importDefault(require("mysql2/promise"));
const pool = promise_1.default.createPool({
    host: process.env.dbHost || "",
    user: process.env.dbUser || "",
    database: process.env.database || "",
    password: process.env.password || ""
});
class MySqlConnection extends DBConnection_js_1.default {
    constructor(conn) {
        super();
        this.conn = conn;
    }
    insert(sql_1) {
        return __awaiter(this, arguments, void 0, function* (sql, params = []) {
            const [result] = yield this.conn.execute(sql, params);
            return result.insertId;
        });
    }
    update(sql, params) {
        return __awaiter(this, void 0, void 0, function* () {
            const [result] = yield this.conn.execute(sql, params);
            return result.changedRows;
        });
    }
    selectSingle(sql, params) {
        return __awaiter(this, void 0, void 0, function* () {
            const [rows] = yield this.conn.execute(sql, params);
            if (rows.length == 0) {
                return null;
            }
            const row = rows[0];
            const value = Object.values(row)[0];
            return value;
        });
    }
    selectRow(sql, params) {
        return __awaiter(this, void 0, void 0, function* () {
            const [rows] = yield this.conn.execute(sql, params);
            if (rows.length == 0) {
                return null;
            }
            const row = rows[0];
            const values = Object.values(row);
            return values;
        });
    }
    selectAll(sql_1) {
        return __awaiter(this, arguments, void 0, function* (sql, params = []) {
            const [rows] = yield this.conn.execute(sql, params);
            return rows;
        });
    }
    beginTransaction() {
        return __awaiter(this, void 0, void 0, function* () {
            yield this.conn.beginTransaction();
        });
    }
    commit() {
        return __awaiter(this, void 0, void 0, function* () {
            yield this.conn.commit();
        });
    }
    rollback() {
        return __awaiter(this, void 0, void 0, function* () {
            yield this.conn.rollback();
        });
    }
    release() {
        this.conn.release();
    }
}
exports.MySqlConnection = MySqlConnection;
function getMySqlConnection() {
    return __awaiter(this, void 0, void 0, function* () {
        const conn = yield pool.getConnection();
        return new MySqlConnection(conn);
    });
}
