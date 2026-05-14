"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
class DBConnection {
    insert(sql, params = []) {
        return new Promise(function (resolve) { resolve(-1); });
    }
    update(sql, params = []) {
        return new Promise(function (resolve) { resolve(-1); });
    }
    selectSingle(sql, params = []) {
        return new Promise(function (resolve) { resolve(null); });
    }
    selectRow(sql, params = []) {
        return new Promise(function (resolve) { resolve(null); });
    }
    selectAll(sql, params = []) {
        return new Promise(function (resolve) { resolve(new Array()); });
    }
    beginTransaction() {
        return new Promise(function (resolve) { resolve(undefined); });
    }
    commit() {
        return new Promise(function (resolve) { resolve(undefined); });
    }
    rollback() {
        return new Promise(function (resolve) { resolve(undefined); });
    }
    release() {
    }
}
exports.default = DBConnection;
