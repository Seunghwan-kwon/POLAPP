"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
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
const socket_io_1 = require("socket.io");
const express_1 = __importDefault(require("express"));
const express_session_1 = __importDefault(require("express-session"));
const Case_js_1 = __importDefault(require("./Case.js"));
const User_js_1 = __importDefault(require("./User.js"));
const Officer_js_1 = __importDefault(require("./Officer.js"));
const AppServer_js_1 = __importStar(require("./AppServer.js"));
const PendingMessage_1 = __importDefault(require("./PendingMessage"));
const http = __importStar(require("node:http"));
const app = (0, express_1.default)();
app.use(express_1.default.static("public"));
app.use(express_1.default.json());
function getPortPrefix() {
    return (Number(process.env.portPrefix) || 0);
}
app.use((req, res, next) => {
    const origin = req.headers.origin;
    const domain = process.env.domain || "localhost";
    const portPrefix = getPortPrefix();
    const allowedOrigins = [];
    allowedOrigins.push(`http://${domain}:${portPrefix + 80}`);
    if (origin && allowedOrigins.includes(origin)) {
        res.header("Access-Control-Allow-Origin", origin);
    }
    res.header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
    res.header("Access-Control-Allow-Headers", "Content-Type");
    if (req.method === "OPTIONS") {
        return res.sendStatus(200);
    }
    next();
});
const sessionMiddleware = (0, express_session_1.default)({
    secret: process.env.sessionSecret || "s2e3cr1et",
    resave: false,
    saveUninitialized: false,
    cookie: {
        httpOnly: true,
        secure: false,
        maxAge: 1000 * 3600
    }
});
app.use(sessionMiddleware);
const httpServer = http.createServer(app);
const io = new socket_io_1.Server(httpServer);
io.engine.use(sessionMiddleware);
class Admin {
    static create(userId) {
        return __awaiter(this, void 0, void 0, function* () {
        });
    }
}
app.post("/case/assignOfficer", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    const { caseId, officerId } = req.body;
    const updatedBy = (_a = req.session) === null || _a === void 0 ? void 0 : _a.userId;
    if (updatedBy == null) {
        res.json({
            code: -1
        });
        return;
    }
    let conn;
    try {
        conn = yield (0, AppServer_js_1.getDBConnection)();
        let _case = yield Case_js_1.default.getCached(caseId, conn);
        if (_case == null) {
            res.json({ code: -2 });
            return;
        }
        const result = yield _case.assignOfficer(officerId, updatedBy);
        res.json({
            code: 0,
            result: result
        });
    }
    catch (e) {
        console.error(e);
        res.json({ code: -2 });
    }
    finally {
        conn === null || conn === void 0 ? void 0 : conn.release();
    }
}));
app.post("/case", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    const { name } = req.body;
    if (name == null || name.length == 0) {
        res.json({ code: -1 });
        return;
    }
    const createdBy = (_a = req.session) === null || _a === void 0 ? void 0 : _a.userId;
    if (createdBy == null) {
        res.json({ code: -2 });
        return;
    }
    try {
        const conn = yield (0, AppServer_js_1.getDBConnection)();
        const _case = yield Case_js_1.default.create(name, createdBy, conn);
        if (_case == null) {
            res.json({ code: -3 });
            return;
        }
        res.json({
            code: 0,
            caseId: _case.id
        });
    }
    catch (e) {
        console.error(e);
        res.json({ code: -4 });
    }
}));
app.put("/case/:id/setComplete", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    const { id } = req.params;
    const updatedBy = (_a = req.session) === null || _a === void 0 ? void 0 : _a.userId;
    if (updatedBy == null) {
        res.json({
            code: -1
        });
        return;
    }
    let conn;
    try {
        conn = yield (0, AppServer_js_1.getDBConnection)();
        const _case = yield Case_js_1.default.getCached(Number(id), conn);
        if (_case == null) {
            res.json({
                code: -2
            });
            return;
        }
        const result = yield _case.setComplete(updatedBy);
        res.json({
            code: 0,
            result: result
        });
    }
    catch (e) {
        console.error(e);
        res.json({
            code: -2
        });
    }
    finally {
        conn === null || conn === void 0 ? void 0 : conn.release();
    }
}));
app.post("/user", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    const { email, passwd, name } = req.body;
    if (email == null || email.length == 0) {
        res.json({
            code: -1
        });
        return;
    }
    if (passwd == null || passwd.length == 0) {
        res.json({ code: -1 });
        return;
    }
    const createdBy = (_a = req.session) === null || _a === void 0 ? void 0 : _a.userId;
    if (createdBy == null) {
        res.json({
            code: -1
        });
        return;
    }
    let conn;
    try {
        conn = yield (0, AppServer_js_1.getDBConnection)();
        const result = yield User_js_1.default.create(conn, email, passwd, createdBy, name);
        if (result.code < 0) {
            res.json({ code: -2 });
            return;
        }
        res.json({
            code: 0,
            result: result
        });
    }
    catch (e) {
        console.error(e);
        res.json({ code: -2 });
    }
    finally {
        conn === null || conn === void 0 ? void 0 : conn.release();
    }
}));
app.post("/user/login", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { email, passwd } = req.body;
    if (email == null || email.length == 0) {
        res.json({
            code: -1
        });
        return;
    }
    if (passwd == null || passwd.length == 0) {
        res.json({
            code: -2
        });
        return;
    }
    let conn;
    try {
        conn = yield (0, AppServer_js_1.getDBConnection)();
        const result = yield User_js_1.default.login(conn, email, passwd);
        if (result.code == 0) {
            req.session.userId = result.userId;
        }
        res.json({
            code: 0,
            result: result
        });
    }
    catch (e) {
        res.json({
            code: -3
        });
    }
    finally {
        conn === null || conn === void 0 ? void 0 : conn.release();
    }
}));
app.delete("/user/:id", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    const { id } = req.params;
    const createdBy = (_a = req.session) === null || _a === void 0 ? void 0 : _a.userId;
    if (createdBy == null) {
        res.json({
            code: -1
        });
        return;
    }
    try {
        const conn = yield (0, AppServer_js_1.getDBConnection)();
        const result = yield User_js_1.default.remove(conn, id, createdBy);
        res.json({
            code: 0,
            result: result
        });
    }
    catch (ex) {
        console.error(ex);
        res.json({ code: -2 });
    }
}));
app.post("/officer", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    const { userId, code } = req.body;
    const createdBy = (_a = req.session) === null || _a === void 0 ? void 0 : _a.userId;
    if (createdBy == null) {
        res.json({
            code: -1
        });
        return;
    }
    let conn;
    try {
        conn = yield (0, AppServer_js_1.getDBConnection)();
        const result = yield Officer_js_1.default.create(conn, userId, code, createdBy);
        res.json({
            code: 0,
            result: result
        });
    }
    catch (e) {
        console.error(e);
        res.json({ code: -2 });
    }
    finally {
        conn === null || conn === void 0 ? void 0 : conn.release();
    }
}));
app.delete("/officer/:id", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    const { id } = req.params;
    const updatedBy = (_a = req.session) === null || _a === void 0 ? void 0 : _a.userId;
    if (updatedBy == null) {
        res.json({
            code: -1
        });
        return;
    }
    try {
        const conn = yield (0, AppServer_js_1.getDBConnection)();
        let officer = yield Officer_js_1.default.getCached(id, conn);
        if (officer == null) {
            res.json({ code: -2 });
            return;
        }
        const result = yield officer.remove(updatedBy);
        res.json({
            code: 0,
            result: result
        });
    }
    catch (e) {
        console.error(e);
        res.json({ code: -3 });
    }
}));
const port = getPortPrefix() + 80;
const appServer = new AppServer_js_1.default();
io.on("connection", (socket) => {
    const session = socket.request.session;
    console.log("Connected");
    let officer = null;
    socket.on("join", (_a) => __awaiter(void 0, [_a], void 0, function* ({ officerId, region, role }) {
        console.log(`[socket.on join] officerId=${officerId},region=${region},role=${role}`);
        officer = yield appServer.setOfficerJoined(officerId, region, role, socket);
        if (officer == null) {
            console.log(`[socket.on join] Failed. officerId=${officerId},region=${region},role=${role}`);
        }
    }));
    socket.on("sendMyLocation", ({ officerId, region, latitude, longitude }) => {
        if (officer == null) {
            console.log("[socket.on sendMyLocation] officer=null");
            socket.disconnect();
            return;
        }
        if (officer.region == null) {
            return;
        }
        officer.updateLocation(latitude, longitude);
        appServer.setOfficerLocationUpdated(officer);
    });
    socket.on("sendRadioMessage", ({ officerId, region, message, timestamp }) => {
        if (officer == null) {
            console.log("[socket.on sendRadioMessage] officer=null");
            socket.disconnect();
            return;
        }
        if (officer.region == null) {
            return;
        }
        const pendingMessage = new PendingMessage_1.default(officer, message, timestamp);
        appServer.pushPendingMessage(pendingMessage);
    });
    socket.on("disconnect", (reason) => {
        console.log("[socket.on disconnect]");
        if (officer == null) {
            socket.disconnect();
            return;
        }
        officer.removeSocket(socket);
        if (officer.isOffline()) {
            appServer.setOfficerOffline(officer);
        }
    });
});
appServer.loop();
httpServer.listen(port, () => {
    console.log(`Listening on port=${port}`);
});
