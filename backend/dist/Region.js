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
const Utils_js_1 = require("./Utils.js");
class Region {
    constructor(id, code) {
        this.id = id;
        this.code = code;
        this.officers = new Map();
    }
    addOfficer(officer) {
        this.officers.set(officer.id, officer);
        console.log(`[${(0, Utils_js_1.getDateStr)()}] [Region.addOfficer] code=${this.code},officer.code=${officer.code},size=${this.officers.size}`);
    }
    removeOfficer(officer) {
        this.officers.delete(officer.id);
    }
    static getCached(id, conn) {
        return __awaiter(this, void 0, void 0, function* () {
            let region = Region.cached.get(id);
            if (region === undefined) {
                const code = yield conn.selectSingle("select code from tblRegion where id=? limit 1;", [id]);
                if (code == null) {
                    Region.cached.set(id, null);
                    return null;
                }
                else {
                    region = new Region(id, code);
                    Region.cached.set(id, region);
                }
            }
            return region;
        });
    }
    static findByCode(code, conn) {
        return __awaiter(this, void 0, void 0, function* () {
            const id = yield conn.selectSingle("select id from tblRegion where code=? limit 1;", [code]);
            if (id == null) {
                return null;
            }
            return yield Region.getCached(id, conn);
        });
    }
}
Region.cached = new Map();
exports.default = Region;
