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
const Police_js_1 = __importDefault(require("./Police.js"));
const http = __importStar(require("http"));
const app = (0, express_1.default)();
app.use(express_1.default.static("public"));
app.use(express_1.default.json());
const sessionMiddleware = (0, express_session_1.default)({
    secret: "se-ssi-on sEcREt ke!Y",
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
app.post("/case/assignPolice", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    const { caseId, policeId } = req.body;
    const updatedBy = (_a = req.session) === null || _a === void 0 ? void 0 : _a.userId;
    if (updatedBy == null) {
        res.json({
            code: -1
        });
        return;
    }
    const assignResult = yield Case_js_1.default.assignPolice(caseId, policeId, updatedBy);
    res.json({
        code: 0,
        result: assignResult
    });
}));
app.post("/case", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { caseName } = req.body;
    const caseCreateResult = yield Case_js_1.default.create(caseName);
    res.json({
        code: 0,
        result: caseCreateResult
    });
}));
app.post("/case/setComplete", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    const { caseId } = req.body;
    const updatedBy = (_a = req.session) === null || _a === void 0 ? void 0 : _a.userId;
    if (updatedBy == null) {
        res.json({
            code: -1
        });
        return;
    }
    const setCaseCompleteResult = yield Case_js_1.default.setComplete(caseId, updatedBy);
    res.json({
        code: 0,
        result: setCaseCompleteResult
    });
}));
app.post("/user", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    const { email, passwd, name } = req.body;
    const createdBy = (_a = req.session) === null || _a === void 0 ? void 0 : _a.userId;
    if (createdBy == null) {
        res.json({
            code: -1
        });
        return;
    }
    const userCreateResult = yield User_js_1.default.create(email, passwd, createdBy, name);
    res.json({
        code: 0,
        result: userCreateResult
    });
}));
app.post("/user/login", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    const { email, passwd } = req.body;
    if (email == null || passwd == null) {
        res.json({
            code: -1
        });
        return;
    }
    const loginResult = yield User_js_1.default.login(email, passwd);
    if (loginResult.code == 0) {
        req.session.userId = loginResult.userId;
    }
    res.json({
        code: 0,
        result: loginResult
    });
}));
app.delete("/user/:userId", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    const { userId } = req.params;
    const createdBy = (_a = req.session) === null || _a === void 0 ? void 0 : _a.userId;
    if (createdBy == null) {
        res.json({
            code: -1
        });
        return;
    }
    const deleteUserResult = yield User_js_1.default.remove(userId, createdBy);
    res.json({
        code: 0,
        result: deleteUserResult
    });
}));
app.post("/police", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    const { userId, officerId } = req.body;
    const createdBy = (_a = req.session) === null || _a === void 0 ? void 0 : _a.userId;
    if (createdBy == null) {
        res.json({
            code: -1
        });
        return;
    }
    const createPoliceResult = yield Police_js_1.default.create(userId, officerId, createdBy);
    res.json({
        code: 0,
        result: createPoliceResult
    });
}));
app.delete("/police/:policeId", (req, res) => __awaiter(void 0, void 0, void 0, function* () {
    var _a;
    const { policeId } = req.params;
    const updatedBy = (_a = req.session) === null || _a === void 0 ? void 0 : _a.userId;
    if (updatedBy == null) {
        res.json({
            code: -1
        });
        return;
    }
    const removePoliceResult = yield Police_js_1.default.remove(policeId, updatedBy);
    res.json({
        code: 0,
        result: removePoliceResult
    });
}));
const sockets = new Map();
let port = 8080;
let lastPositionSyncTime = 0;
const updatedPolices = new Map();
const policeClients = new Map();
function setOfficerUpdated(policeId, x, y) {
    const policeClient = policeClients.get(policeId);
    if (policeClient == null) {
        return;
    }
    policeClient.x = x;
    policeClient.y = y;
    updatedPolices.set(policeId, 1);
}
class PoliceClient {
    constructor(policeId, officerId) {
        this.x = 0;
        this.y = 0;
        this.policeId = policeId;
        this.officerId = officerId;
        this.sockets = new Map();
    }
    addSocket(socket) {
        this.sockets.set(socket.id, socket);
    }
    removeSocket(socketId) {
        this.sockets.delete(socketId);
        return this.sockets.size == 0;
    }
    syncPeerPosition(officerId, x, y) {
        for (const socket of this.sockets.values()) {
            socket.emit("updateColleagueLocation", {
                officerId,
                latitude: x,
                longitude: y
            });
        }
    }
}
function syncOfficerPositions() {
    return __awaiter(this, void 0, void 0, function* () {
        const updatedPoliceIds = updatedPolices.keys();
        for (const policeId of updatedPoliceIds) {
            const police = policeClients.get(policeId);
            if (police == null) {
                console.log("syncOfficerPositions police=null");
                continue;
            }
            /*
            const getCurrentCaseIdResult=await Police.getCurrentCaseId(officerId);
            const caseId=getCurrentCaseIdResult.caseId;
            if(caseId==null){
                continue;
            }
            const getOfficerIdsResult=await Case.getOfficerIds(caseId);
            if(getOfficerIdsResult.code!=GetOfficerIdsResultCode.Success){
                continue;
            }
            const officerIds=getOfficerIdsResult.ids;
               */
            const policeIds = policeClients.keys();
            for (const _policeId of policeIds) {
                if (_policeId === policeId) {
                    continue;
                }
                const peerClient = policeClients.get(_policeId);
                if (peerClient == null) {
                    console.log("syncOfficerPositions peerClient=null");
                    continue;
                }
                peerClient.syncPeerPosition(police.officerId, police.x, police.y);
            }
        }
        updatedPolices.clear();
    });
}
function loop() {
    return __awaiter(this, void 0, void 0, function* () {
        while (true) {
            yield syncOfficerPositions();
            yield new Promise(function (resolve) {
                setTimeout(resolve, 100);
            });
        }
    });
}
function removePoliceSocket(policeId, socketId) {
    const policeClient = policeClients.get(policeId);
    if (policeClient == null) {
        return;
    }
    const offline = policeClient.removeSocket(socketId);
    if (offline) {
        policeClients.delete(policeId);
    }
}
io.on("connection", (socket) => {
    const session = socket.request.session;
    console.log("Connected");
    let socketPoliceId = null;
    socket.on("join", (_a) => __awaiter(void 0, [_a], void 0, function* ({ officerId }) {
        console.log("join officerId=" + officerId);
        const getPoliceIdResult = yield Police_js_1.default.getPoliceId(officerId);
        if (getPoliceIdResult.code != 0) {
            console.log("getPoliceIdResult.code=" + getPoliceIdResult.code);
            return;
        }
        socketPoliceId = getPoliceIdResult.policeId;
        if (socketPoliceId == null) {
            return;
        }
        let policeClient = policeClients.get(socketPoliceId);
        if (policeClient == null) {
            policeClient = new PoliceClient(socketPoliceId, officerId);
            policeClients.set(socketPoliceId, policeClient);
        }
        policeClient.addSocket(socket);
    }));
    socket.on("sendMyLocation", ({ officerId, latitude, longitude }) => {
        if (socketPoliceId == null) {
            return;
        }
        setOfficerUpdated(socketPoliceId, latitude, longitude);
    });
    socket.on("disconnect", (reason) => {
        console.log("disconnected");
        if (socketPoliceId == null) {
            return;
        }
        removePoliceSocket(socketPoliceId, socket.id);
    });
});
httpServer.listen(port, () => {
    console.log("Listening on port=" + port);
});
loop();
