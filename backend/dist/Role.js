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
class Role {
    constructor(id, code) {
        this.id = id;
        this.code = code;
        this.officers = new Map();
    }
    addOfficer(officer) {
        this.officers.set(officer.id, officer);
    }
    removeOfficer(officer) {
        this.officers.delete(officer.id);
    }
    static getCached(id, conn) {
        return __awaiter(this, void 0, void 0, function* () {
            let role = Role.cached.get(id);
            if (role === undefined) {
                const code = yield conn.selectSingle("select code from tblRole where id=? limit 1;", [id]);
                if (code == null) {
                    Role.cached.set(id, null);
                    return null;
                }
                else {
                    role = new Role(id, code);
                    Role.cached.set(id, role);
                }
            }
            return role;
        });
    }
    static findByCode(code, conn) {
        return __awaiter(this, void 0, void 0, function* () {
            const id = yield conn.selectSingle("select id from tblRole where code=? limit 1;", [code]);
            if (id == null) {
                return null;
            }
            return yield Role.getCached(id, conn);
        });
    }
}
Role.cached = new Map();
exports.default = Role;
