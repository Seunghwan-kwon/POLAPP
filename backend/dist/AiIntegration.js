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
exports.normalizeThreatInput = normalizeThreatInput;
exports.normalizeDetections = normalizeDetections;
exports.registerAiIntegration = registerAiIntegration;
const express_1 = __importDefault(require("express"));
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const AppServer_js_1 = require("./AppServer.js");
const Officer_js_1 = __importDefault(require("./Officer.js"));
const cameraStreams = new Map();
const cameraStreamTimeoutMs = 8000;
function textValue(value, maxLength) {
    return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}
function numberValue(value) {
    const result = typeof value === "number" ? value : Number(value);
    return Number.isFinite(result) ? result : null;
}
function normalizeThreatInput(value) {
    if (value == null || typeof value !== "object") {
        return null;
    }
    const body = value;
    const eventId = textValue(body.eventId, 200);
    const sessionId = textValue(body.sessionId, 120) || null;
    const category = textValue(body.category, 80) || "unknown";
    const alertLabel = textValue(body.alertLabel, 80) || "위협";
    const riskLevel = numberValue(body.riskLevel);
    const evidenceIndex = numberValue(body.evidenceIndex);
    const occurredAt = new Date(textValue(body.occurredAt, 80));
    if (!eventId || riskLevel == null || !Number.isInteger(riskLevel) || riskLevel < 1 || riskLevel > 4 || evidenceIndex == null || Number.isNaN(occurredAt.getTime())) {
        return null;
    }
    const rawReasons = Array.isArray(body.reasons) ? body.reasons : [];
    const reasons = rawReasons
        .map(reason => textValue(reason, 240))
        .filter(reason => reason.length > 0)
        .slice(0, 8);
    const rawLatitude = numberValue(body.latitude);
    const rawLongitude = numberValue(body.longitude);
    const latitude = rawLatitude != null && rawLatitude >= -90 && rawLatitude <= 90 ? rawLatitude : null;
    const longitude = rawLongitude != null && rawLongitude >= -180 && rawLongitude <= 180 ? rawLongitude : null;
    return {
        eventId,
        sessionId,
        category,
        alertLabel,
        riskLevel,
        evidenceIndex: Math.max(0, Math.min(100, evidenceIndex)),
        reasons,
        latitude,
        longitude,
        occurredAt
    };
}
function normalizeDetections(value) {
    var _a;
    if (!Array.isArray(value)) {
        return [];
    }
    const result = [];
    for (const raw of value.slice(0, 8)) {
        if (raw == null || typeof raw !== "object") {
            continue;
        }
        const item = raw;
        if (item.label !== "knife" && item.label !== "bottle") {
            continue;
        }
        const score = (_a = numberValue(item.score)) !== null && _a !== void 0 ? _a : 0;
        const rawBox = Array.isArray(item.box) ? item.box : [];
        const box = rawBox.length === 4
            ? rawBox.map(numberValue).map(coordinate => Math.max(0, Math.min(1, coordinate !== null && coordinate !== void 0 ? coordinate : 0)))
            : [];
        result.push({
            label: item.label,
            displayLabel: item.label === "knife" ? "칼" : "병",
            score: Math.max(0, Math.min(1, score)),
            box
        });
    }
    return result;
}
function officerIdFromRequest(req, getJwtSecret) {
    var _a;
    const sessionOfficerId = Number((_a = req.session) === null || _a === void 0 ? void 0 : _a.officerId);
    if (Number.isInteger(sessionOfficerId) && sessionOfficerId > 0) {
        return sessionOfficerId;
    }
    const header = req.headers.authorization;
    if (!(header === null || header === void 0 ? void 0 : header.startsWith("Bearer "))) {
        return null;
    }
    try {
        const decoded = jsonwebtoken_1.default.verify(header.slice(7), getJwtSecret());
        return Number.isInteger(decoded.officerId) && decoded.officerId > 0 ? decoded.officerId : null;
    }
    catch (_b) {
        return null;
    }
}
function officerForRequest(req, options) {
    return __awaiter(this, void 0, void 0, function* () {
        const officerId = officerIdFromRequest(req, options.getJwtSecret);
        if (officerId == null) {
            return null;
        }
        let conn;
        try {
            conn = yield (0, AppServer_js_1.getDBConnection)();
            return yield Officer_js_1.default.getCached(officerId, conn, options.appServer);
        }
        finally {
            conn === null || conn === void 0 ? void 0 : conn.release();
        }
    });
}
function requireOfficer(req_1, res_1, options_1) {
    return __awaiter(this, arguments, void 0, function* (req, res, options, admin = false) {
        var _a;
        const officer = yield officerForRequest(req, options);
        if (officer == null) {
            res.status(401).json({ code: 401, message: "Authentication required" });
            return null;
        }
        if (admin && ((_a = officer.role) === null || _a === void 0 ? void 0 : _a.code) !== "ADMIN") {
            res.status(403).json({ code: 403, message: "Administrator permission required" });
            return null;
        }
        return officer;
    });
}
function isoValue(value) {
    const parsed = value instanceof Date ? value : new Date(value);
    return Number.isNaN(parsed.getTime()) ? String(value) : parsed.toISOString();
}
function threatPayload(row, officer) {
    var _a;
    var _b;
    let reasons = [];
    try {
        const parsed = JSON.parse(row.reasonsJson);
        reasons = Array.isArray(parsed) ? parsed.map(String) : [];
    }
    catch (_c) { }
    return {
        id: Number(row.id),
        eventId: row.eventId,
        sessionId: row.sessionId,
        officerId: officer.code,
        officerName: officer.name,
        rank: officer.rank,
        region: (_b = (_a = officer.region) === null || _a === void 0 ? void 0 : _a.code) !== null && _b !== void 0 ? _b : "",
        category: row.category,
        alertLabel: row.alertLabel,
        riskLevel: Number(row.riskLevel),
        evidenceIndex: Number(row.evidenceIndex),
        reasons,
        latitude: row.latitude == null ? null : Number(row.latitude),
        longitude: row.longitude == null ? null : Number(row.longitude),
        occurredAt: isoValue(row.occurredAt),
        createdAt: isoValue(row.createdAt)
    };
}
function emitToAdmins(appServer, event, payload) {
    return __awaiter(this, void 0, void 0, function* () {
        const adminRole = yield appServer.getAdminRole();
        if (adminRole == null) {
            return;
        }
        for (const officer of adminRole.officers.values()) {
            officer.emit(event, payload);
        }
    });
}
function cameraPayload(stream) {
    return {
        officerId: stream.officerId,
        officerName: stream.officerName,
        rank: stream.rank,
        region: stream.region,
        sessionId: stream.sessionId,
        updatedAt: stream.updatedAt,
        detections: stream.detections
    };
}
function pruneCameraStreams() {
    const now = Date.now();
    for (const [officerId, stream] of cameraStreams) {
        if (now - stream.lastSeen > cameraStreamTimeoutMs) {
            cameraStreams.delete(officerId);
        }
    }
}
function registerAiIntegration(options) {
    const { app, appServer } = options;
    const jpegBody = express_1.default.raw({ type: "image/jpeg", limit: "700kb" });
    app.get("/health", (_req, res) => {
        res.json({ status: "ok", service: "polapp-backend" });
    });
    app.post("/threat-alerts", (req, res) => __awaiter(this, void 0, void 0, function* () {
        var _a, _b;
        try {
            const officer = yield requireOfficer(req, res, options);
            if (officer == null)
                return;
            const input = normalizeThreatInput(req.body);
            if (input == null) {
                res.status(400).json({ code: 400, message: "Invalid threat alert payload" });
                return;
            }
            const latitude = (_a = input.latitude) !== null && _a !== void 0 ? _a : (officer.x !== 0 ? officer.x : null);
            const longitude = (_b = input.longitude) !== null && _b !== void 0 ? _b : (officer.y !== 0 ? officer.y : null);
            let conn;
            try {
                conn = yield (0, AppServer_js_1.getDBConnection)();
                const insertId = yield conn.insert(`
					INSERT IGNORE INTO tblThreatAlert(
						eventId,officerId,sessionId,category,alertLabel,riskLevel,
						evidenceIndex,reasonsJson,latitude,longitude,occurredAt
					)VALUES(?,?,?,?,?,?,?,?,?,?,?);
				`, [
                    input.eventId, officer.id, input.sessionId, input.category, input.alertLabel,
                    input.riskLevel, input.evidenceIndex, JSON.stringify(input.reasons),
                    latitude, longitude, input.occurredAt
                ]);
                const rows = yield conn.selectAll("SELECT id,eventId,officerId,sessionId,category,alertLabel,riskLevel,evidenceIndex,reasonsJson,latitude,longitude,occurredAt,createdAt FROM tblThreatAlert WHERE eventId=? LIMIT 1;", [input.eventId]);
                if (rows.length === 0) {
                    throw new Error("Threat alert was not found after insert");
                }
                const storedOfficer = yield Officer_js_1.default.getCached(Number(rows[0].officerId), conn, appServer);
                if (storedOfficer == null) {
                    throw new Error("Threat alert officer was not found");
                }
                const payload = threatPayload(rows[0], storedOfficer);
                const created = insertId > 0;
                if (created) {
                    yield emitToAdmins(appServer, "threatDetected", payload);
                }
                res.status(created ? 201 : 200).json({ code: 0, result: payload, created });
            }
            finally {
                conn === null || conn === void 0 ? void 0 : conn.release();
            }
        }
        catch (error) {
            console.error("[AI integration] POST /threat-alerts", error);
            if (!res.headersSent)
                res.status(500).json({ code: 500, message: "Server error" });
        }
    }));
    app.get("/threat-alerts", (req, res) => __awaiter(this, void 0, void 0, function* () {
        var _a;
        try {
            const admin = yield requireOfficer(req, res, options, true);
            if (admin == null)
                return;
            const requestedLimit = Number((_a = req.query.limit) !== null && _a !== void 0 ? _a : 50);
            const limit = Number.isFinite(requestedLimit) ? Math.max(1, Math.min(200, Math.trunc(requestedLimit))) : 50;
            let conn;
            try {
                conn = yield (0, AppServer_js_1.getDBConnection)();
                const rows = yield conn.selectAll(`SELECT id,eventId,officerId,sessionId,category,alertLabel,riskLevel,evidenceIndex,reasonsJson,latitude,longitude,occurredAt,createdAt
					 FROM tblThreatAlert ORDER BY createdAt DESC LIMIT ${limit};`, []);
                const result = [];
                for (const row of rows) {
                    const officer = yield Officer_js_1.default.getCached(Number(row.officerId), conn, appServer);
                    if (officer != null)
                        result.push(threatPayload(row, officer));
                }
                res.json({ code: 0, result });
            }
            finally {
                conn === null || conn === void 0 ? void 0 : conn.release();
            }
        }
        catch (error) {
            console.error("[AI integration] GET /threat-alerts", error);
            if (!res.headersSent)
                res.status(500).json({ code: 500, message: "Server error" });
        }
    }));
    app.post("/camera-stream/status", (req, res) => __awaiter(this, void 0, void 0, function* () {
        var _a, _b, _c;
        var _d, _e, _f;
        try {
            const officer = yield requireOfficer(req, res, options);
            if (officer == null)
                return;
            const sessionId = textValue((_a = req.body) === null || _a === void 0 ? void 0 : _a.sessionId, 120);
            if (!sessionId) {
                res.status(400).json({ code: 400, message: "Camera session is required" });
                return;
            }
            const enabled = ((_b = req.body) === null || _b === void 0 ? void 0 : _b.enabled) === true;
            let payload;
            let event;
            if (enabled) {
                const previous = cameraStreams.get(officer.code);
                const sameSession = (previous === null || previous === void 0 ? void 0 : previous.sessionId) === sessionId;
                const stream = {
                    officerId: officer.code,
                    officerName: officer.name,
                    rank: officer.rank,
                    region: (_d = (_c = officer.region) === null || _c === void 0 ? void 0 : _c.code) !== null && _d !== void 0 ? _d : "",
                    sessionId,
                    updatedAt: new Date().toISOString(),
                    detections: sameSession ? (_e = previous === null || previous === void 0 ? void 0 : previous.detections) !== null && _e !== void 0 ? _e : [] : [],
                    frame: sameSession ? (_f = previous === null || previous === void 0 ? void 0 : previous.frame) !== null && _f !== void 0 ? _f : null : null,
                    lastSeen: Date.now()
                };
                cameraStreams.set(officer.code, stream);
                payload = cameraPayload(stream);
                event = "cameraStreamUpdated";
            }
            else {
                cameraStreams.delete(officer.code);
                payload = { officerId: officer.code, sessionId };
                event = "cameraStreamStopped";
            }
            yield emitToAdmins(appServer, event, payload);
            res.json({ code: 0, result: payload });
        }
        catch (error) {
            console.error("[AI integration] POST /camera-stream/status", error);
            if (!res.headersSent)
                res.status(500).json({ code: 500, message: "Server error" });
        }
    }));
    app.post("/camera-stream/frame", jpegBody, (req, res) => __awaiter(this, void 0, void 0, function* () {
        var _a;
        var _b;
        try {
            const officer = yield requireOfficer(req, res, options);
            if (officer == null)
                return;
            const sessionId = textValue(req.query.sessionId, 120);
            const frame = Buffer.isBuffer(req.body) ? req.body : null;
            if (!sessionId || frame == null || frame.length === 0) {
                res.status(400).json({ code: 400, message: "Camera frame and session are required" });
                return;
            }
            if (frame.length < 4 || frame[0] !== 0xff || frame[1] !== 0xd8) {
                res.status(400).json({ code: 400, message: "JPEG frame is required" });
                return;
            }
            let rawDetections = [];
            try {
                rawDetections = JSON.parse(textValue(req.query.detections, 10000) || "[]");
            }
            catch (_c) { }
            const stream = {
                officerId: officer.code,
                officerName: officer.name,
                rank: officer.rank,
                region: (_b = (_a = officer.region) === null || _a === void 0 ? void 0 : _a.code) !== null && _b !== void 0 ? _b : "",
                sessionId,
                updatedAt: new Date().toISOString(),
                detections: normalizeDetections(rawDetections),
                frame,
                lastSeen: Date.now()
            };
            cameraStreams.set(officer.code, stream);
            const payload = cameraPayload(stream);
            yield emitToAdmins(appServer, "cameraStreamUpdated", payload);
            res.status(202).json({ code: 0, result: payload });
        }
        catch (error) {
            console.error("[AI integration] POST /camera-stream/frame", error);
            if (!res.headersSent)
                res.status(500).json({ code: 500, message: "Server error" });
        }
    }));
    app.get("/camera-streams", (req, res) => __awaiter(this, void 0, void 0, function* () {
        try {
            const admin = yield requireOfficer(req, res, options, true);
            if (admin == null)
                return;
            pruneCameraStreams();
            const result = [...cameraStreams.values()]
                .filter(stream => stream.frame != null)
                .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
                .map(cameraPayload);
            res.json({ code: 0, result });
        }
        catch (error) {
            console.error("[AI integration] GET /camera-streams", error);
            if (!res.headersSent)
                res.status(500).json({ code: 500, message: "Server error" });
        }
    }));
    app.get("/camera-streams/:officerCode/frame", (req, res) => __awaiter(this, void 0, void 0, function* () {
        var _a;
        try {
            const admin = yield requireOfficer(req, res, options, true);
            if (admin == null)
                return;
            pruneCameraStreams();
            const frame = (_a = cameraStreams.get(req.params.officerCode)) === null || _a === void 0 ? void 0 : _a.frame;
            if (frame == null) {
                res.status(404).json({ code: 404, message: "Active camera frame not found" });
                return;
            }
            res.set({
                "Content-Type": "image/jpeg",
                "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
                "Pragma": "no-cache"
            });
            res.send(frame);
        }
        catch (error) {
            console.error("[AI integration] GET /camera-streams/:officerCode/frame", error);
            if (!res.headersSent)
                res.status(500).json({ code: 500, message: "Server error" });
        }
    }));
}
