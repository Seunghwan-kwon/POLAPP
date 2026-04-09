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
class SQLHelper {
    static insert(sql, conn, params) {
        return __awaiter(this, void 0, void 0, function* () {
            const [result] = yield conn.execute(sql, params);
            return result.insertId;
        });
    }
    static selectAll(sql, conn, params) {
        return __awaiter(this, void 0, void 0, function* () {
            const [rows] = yield conn.execute(sql, params);
            return rows;
        });
    }
    static selectSingle(sql, conn, params) {
        return __awaiter(this, void 0, void 0, function* () {
            const [rows] = yield conn.execute(sql, params);
            if (rows.length == 0) {
                return null;
            }
            const row = rows[0];
            const value = Object.values(row)[0];
            return value;
        });
    }
    static selectRow(sql, conn, params) {
        return __awaiter(this, void 0, void 0, function* () {
            const [rows] = yield conn.execute(sql, params);
            if (rows.length == 0) {
                return null;
            }
            const row = rows[0];
            return row;
        });
    }
    static execute(sql, conn, params) {
        return __awaiter(this, void 0, void 0, function* () {
            const [result] = yield conn.execute(sql, params);
            return result.changedRows;
        });
    }
}
exports.default = SQLHelper;
