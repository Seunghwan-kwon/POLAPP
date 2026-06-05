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
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const socket_io_1 = require("socket.io");
const express_1 = __importDefault(require("express"));
const express_session_1 = __importDefault(require("express-session"));
const Report_js_1 = __importDefault(require("./Report.js"));
const Region_js_1 = __importDefault(require("./Region.js"));
const Role_js_1 = __importDefault(require("./Role.js"));
const Officer_js_1 = __importDefault(require("./Officer.js"));
const AppServer_js_1 = __importStar(require("./AppServer.js"));
const http = __importStar(require("node:http"));
const fs = __importStar(require("node:fs"));
//import*as readline from"node:readline";
const Utils_js_1 = require("./Utils.js");
const app = (0, express_1.default)();
let startTime = new Date();
let buildTime = new Date();
app.set("trust proxy", 1);
app.use(express_1.default.static("public"));
app.use(express_1.default.json());
function getPortPrefix() {
    return (Number(process.env.portPrefix) || 0);
}
app.use((req, res, next) => {
    const origin = req.headers.origin;
    const domain = process.env.domain || "localhost";
    const portPrefix = getPortPrefix();
    /*
    const allowedOrigins=[];
    allowedOrigins.push(`http://${domain}:${portPrefix+80}`);
    */
    //if(origin&&allowedOrigins.includes(origin)){
    res.header("Access-Control-Allow-Origin", origin);
    //}
    res.header("Access-Control-Allow-Credentials", "true");
    res.header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, PATCH");
    res.header("Access-Control-Allow-Headers", "Content-Type, Authorization");
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
        secure: true,
        sameSite: "none",
        maxAge: 1000 * 3600
    }
});
app.use(sessionMiddleware);
const httpServer = http.createServer(app);
const io = new socket_io_1.Server(httpServer);
io.engine.use(sessionMiddleware);
app.get("/info", (req, res) => {
    res.json({ startTime: (0, Utils_js_1.getDateStr)(startTime), buildTime: (0, Utils_js_1.getDateStr)(buildTime) });
});
app.post("/login", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    const { officerId, matchingCode } = req.body;
    console.log(`[${(0, Utils_js_1.getDateStr)()}] /login officerId=${officerId},matchingCode=${matchingCode}`);
    if (officerId == null) {
        res.json({ code: -1 });
        return;
    }
    if (matchingCode == null) {
        res.json({ code: -2 });
        return;
    }
    let conn;
    try {
        conn = yield (0, AppServer_js_1.getDBConnection)();
        const officer = yield Officer_js_1.default.findByCode(conn, officerId, appServer);
        const failPayload = {
            status: "fail",
            message: "사번 또는 코드가 일치하지 않습니다."
        };
        if (!officer) {
            res.status(401).json(failPayload);
            return;
        }
        const officerMatchingCode = yield officer.getMatchingCode(conn);
        if (officerMatchingCode !== matchingCode) {
            res.status(401).json(failPayload);
            return;
        }
        const payload = {
            officerId: officer.id
        };
        const token = jsonwebtoken_1.default.sign(payload, getJwtSecret(), { expiresIn: "1h" });
        req.session.officerId = officer.id;
        res.status(200).json({
            status: "success",
            officerId: officer.code,
            token: token,
            name: officer.name,
            rank: officer.rank,
            region: (_a = officer.region) === null || _a === void 0 ? void 0 : _a.code,
            affiliaton: officer.affiliation
        });
    }
    catch (e) {
        console.error(e);
        res.status(500).json({
            status: "fail",
            message: "서버 오류입니다."
        });
    }
    finally {
        conn === null || conn === void 0 ? void 0 : conn.release();
    }
}));
/*
interface CreateUserRequestBody{
    email:string,
    passwd:string,
    name:string
}
app.post("/user",async(req:Request<{},{},CreateUserRequestBody>,res:Response)=>{
    const{email,passwd,name}=req.body;
    if(email==null||email.length==0){
        res.json({
            code:-1
        });
        return;
    }
    if(passwd==null||passwd.length==0){
        res.json({code:-1});
        return;
    }
    const createdBy=req.session?.officerId;
    if(createdBy==null){
        res.json({
            code:-1
        });
        return;
    }
    let conn;
    try{
        conn=await getDBConnection();
        const result=await User.create(conn,email,passwd,createdBy,name);
        if(result.code<0){
            res.json({code:-2});
            return;
        }
        res.json({
            code:0,
            result:result
        });
    }catch(e){
        console.error(e);
        res.json({code:-2});
    }finally{
        conn?.release();
    }
});
*/
function getJwtSecret() {
    return process.env.jwtSecret || "0000";
}
function authByHeader(authHeader) {
    if (authHeader == null) {
        return -1;
    }
    if (!authHeader.startsWith("Bearer ")) {
        return -2;
    }
    const token = authHeader.split(" ")[1];
    try {
        const decoded = jsonwebtoken_1.default.verify(token, getJwtSecret());
        return decoded.officerId;
    }
    catch (e) {
        console.error(e);
        return -3;
    }
}
app.get("/reports", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    let { status } = req.query;
    const authHeader = req.headers.authorization;
    let requestedBy = (_a = req.session) === null || _a === void 0 ? void 0 : _a.officerId;
    console.log(`[${(0, Utils_js_1.getDateStr)()}] GET /reports requestedBy=${requestedBy},status=${status}`);
    let authType = -1;
    if (requestedBy == null) {
        requestedBy = authByHeader(authHeader || null);
        if (requestedBy < 0) {
            res.json({ code: -1 });
            return;
        }
        else if (requestedBy == null) {
            res.json({ code: -2 });
            return;
        }
        authType = 2;
    }
    else {
        authType = 1;
    }
    let conn;
    try {
        conn = yield (0, AppServer_js_1.getDBConnection)();
        const ids = yield Report_js_1.default.select(conn, status);
        if (ids == null) {
            res.json({ code: -2 });
            return;
        }
        const reports = [];
        for (const id of ids) {
            const report = yield Report_js_1.default.getCached(id, conn);
            reports.push(report);
        }
        res.json({
            code: 0,
            authType,
            result: reports
        });
    }
    catch (e) {
        console.error(e);
        res.json({ code: -3 });
    }
    finally {
        conn === null || conn === void 0 ? void 0 : conn.release();
    }
}));
app.patch("/reports/:reportId/close", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    let { reportId } = req.params;
    const closedBy = (_a = req.session) === null || _a === void 0 ? void 0 : _a.officerId;
    console.log(`[${(0, Utils_js_1.getDateStr)()}] PATCH /reports/${reportId}/close closedBy=${closedBy}`);
    if (closedBy == null) {
        res.json({
            code: -1
        });
        return;
    }
    let conn;
    try {
        conn = yield (0, AppServer_js_1.getDBConnection)();
        const splitted = reportId.split("-");
        let id = 0;
        if (splitted.length == 2) {
            id = Number(splitted[1]);
        }
        else {
            id = Number(reportId);
        }
        const report = yield Report_js_1.default.getCached(id, conn);
        if (report == null) {
            res.json({ code: -2 });
            return;
        }
        const result = yield report.close(closedBy, conn);
        appServer.broadcast("reportClosed", report);
        res.json({
            code: 0,
            result: {
                id: report.id,
                status: "CLOSED",
                closedAt: report.closedAt,
                closedBy: report.closedBy
            }
        });
    }
    catch (e) {
        console.error(e);
        res.json({ code: -3 });
    }
    finally {
        conn === null || conn === void 0 ? void 0 : conn.release();
    }
}));
app.post("/reports", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    const { title, description, severity, status, latitude, longitude } = req.body;
    const createdBy = (_a = req.session) === null || _a === void 0 ? void 0 : _a.officerId;
    console.log(`[${(0, Utils_js_1.getDateStr)()}] POST /reports createdBy=${createdBy},title=${title}`);
    if (createdBy == null) {
        res.json({
            code: -1
        });
        return;
    }
    let conn;
    try {
        conn = yield (0, AppServer_js_1.getDBConnection)();
        const creator = yield Officer_js_1.default.getCached(createdBy, conn, appServer);
        if (creator == null) {
            res.json({ code: -2 });
            return;
        }
        const report = yield Report_js_1.default.create(title, description, severity, latitude, longitude, status, createdBy, new Date(), null, null, conn);
        appServer.broadcast("reportCreated", report);
        res.json({
            code: 0,
            result: report
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
app.post("/officer", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    const { userId, code, name, rank, regionId, roleId, affiliation } = req.body;
    const createdBy = (_a = req.session) === null || _a === void 0 ? void 0 : _a.officerId;
    if (createdBy == null) {
        res.json({
            code: -1
        });
        return;
    }
    let conn;
    try {
        conn = yield (0, AppServer_js_1.getDBConnection)();
        const region = yield Region_js_1.default.getCached(regionId, conn);
        const role = yield Role_js_1.default.getCached(roleId, conn);
        const result = yield Officer_js_1.default.create(conn, userId, code, name, rank, region, role, affiliation, createdBy, appServer);
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
    const updatedBy = (_a = req.session) === null || _a === void 0 ? void 0 : _a.officerId;
    if (updatedBy == null) {
        res.json({
            code: -1
        });
        return;
    }
    let conn;
    try {
        conn = yield (0, AppServer_js_1.getDBConnection)();
        let officer = yield Officer_js_1.default.getCached(id, conn, appServer);
        if (officer == null) {
            res.json({ code: -2 });
            return;
        }
        const result = yield officer.remove(updatedBy, conn);
        res.json({
            code: 0,
            result: result
        });
    }
    catch (e) {
        console.error(e);
        res.json({ code: -3 });
    }
    finally {
        conn === null || conn === void 0 ? void 0 : conn.release();
    }
}));
const port = getPortPrefix() + 80;
const appServer = new AppServer_js_1.default();
console.log("port=" + port);
io.on("connection", (socket) => {
    const forwarded = socket.handshake.headers["x-forwarded-for"];
    let ipAddress;
    if (forwarded) {
        const ipList = Array.isArray(forwarded) ? forwarded[0] : forwarded;
        ipAddress = ipList.split(",")[0].trim();
    }
    else {
        ipAddress = socket.handshake.address;
    }
    const session = socket.request.session;
    console.log(`[${(0, Utils_js_1.getDateStr)()}] [io.on connection] socket.id=${socket.id},ip=${ipAddress}`);
    let officer = null;
    socket.on("join", (_a) => __awaiter(void 0, [_a], void 0, function* ({ officerId }) {
        officer = yield appServer.setOfficerJoined(officerId, socket);
        if (officer == null) {
            console.log(`[${(0, Utils_js_1.getDateStr)()}] [socket.on join]  officerId=${officerId},officer=null Rejected.`);
        }
        console.log(`[${(0, Utils_js_1.getDateStr)()}] [socket.on join] officerId=${officerId},socket.id=${socket.id} Accepted.`);
    }));
    socket.on("sendMyLocation", ({ officerId, region, latitude, longitude }) => {
        if (officer == null) {
            console.log(`[${(0, Utils_js_1.getDateStr)()}] [socket.on sendMyLocation] socket.id=${socket.id},officer=null Rejected.`);
            socket.disconnect();
            return;
        }
        if (officer.region == null) {
            console.log(`[${(0, Utils_js_1.getDateStr)()}] [socket.on sendMyLocation] socket.id=${socket.id},officer.code=${officer.code},officer.region=null Rejected.`);
            return;
        }
        //console.log(`[${getDateStr()}] [socket.on sendMyLocation] socket.id=${socket.id},officer.code=${officer.code},region=${officer.region.code}`);
        officer.setLocation(latitude, longitude);
        appServer.setOfficerLocationUpdated(officer);
    });
    socket.on("sendRadioMessage", (_a) => __awaiter(void 0, [_a], void 0, function* ({ officerId, region, message, timestamp }) {
        if (officer == null) {
            console.log(`[${(0, Utils_js_1.getDateStr)()}] [socket.on sendRadioMessage] socket.id=${socket.id},officer=null Rejected.`);
            socket.disconnect();
            return;
        }
        console.log(`[${(0, Utils_js_1.getDateStr)()}] [socket.on sendRadioMessage] socket.id=${socket.id},officer.code=${officer.code} Accepted.`);
        yield appServer.pushPendingMessage(officer, region, message, timestamp);
    }));
    socket.on("disconnect", (reason) => {
        if (officer == null) {
            console.log(`[${(0, Utils_js_1.getDateStr)()}] [socket.on disconnect] socket.id=${socket.id},officer=null`);
            return;
        }
        console.log(`[${(0, Utils_js_1.getDateStr)()}] [socket.on disconnect] socket.id=${socket.id},officer.code=${officer.code} Accepted`);
        officer.removeSocket(socket);
    });
});
function getBuildTime() {
    const stats = fs.statSync(__filename);
    const createdDate = stats.mtime;
    return createdDate;
}
httpServer.listen(port, () => {
    startTime = new Date();
    buildTime = getBuildTime();
    console.log(`Listening on port=${port}`);
});
