import express,{Application,Request,Response}from"express";
import jwt,{JwtPayload}from"jsonwebtoken";
import AppServer,{getDBConnection}from"./AppServer.js";
import Officer from"./Officer.js";

interface AiIntegrationOptions{
	app:Application;
	appServer:AppServer;
	getJwtSecret:()=>string;
}

interface UserTokenPayload extends JwtPayload{
	officerId:number;
}

interface ThreatInput{
	eventId:string;
	sessionId:string|null;
	category:string;
	alertLabel:string;
	riskLevel:number;
	evidenceIndex:number;
	reasons:string[];
	latitude:number|null;
	longitude:number|null;
	occurredAt:Date;
}

interface ThreatRow{
	id:number;
	eventId:string;
	officerId:number;
	sessionId:string|null;
	category:string;
	alertLabel:string;
	riskLevel:number;
	evidenceIndex:number;
	reasonsJson:string;
	latitude:number|null;
	longitude:number|null;
	occurredAt:Date|string;
	createdAt:Date|string;
}

interface CameraDetection{
	label:"knife"|"bottle";
	displayLabel:string;
	score:number;
	box:number[];
}

interface CameraStream{
	officerId:string;
	officerName:string;
	rank:string;
	region:string;
	sessionId:string;
	updatedAt:string;
	detections:CameraDetection[];
	frame:Buffer|null;
	lastSeen:number;
}

const cameraStreams=new Map<string,CameraStream>();
const cameraStreamTimeoutMs=8000;

function textValue(value:unknown,maxLength:number):string{
	return typeof value==="string"?value.trim().slice(0,maxLength):"";
}

function numberValue(value:unknown):number|null{
	const result=typeof value==="number"?value:Number(value);
	return Number.isFinite(result)?result:null;
}

export function normalizeThreatInput(value:unknown):ThreatInput|null{
	if(value==null||typeof value!=="object"){
		return null;
	}
	const body=value as Record<string,unknown>;
	const eventId=textValue(body.eventId,200);
	const sessionId=textValue(body.sessionId,120)||null;
	const category=textValue(body.category,80)||"unknown";
	const alertLabel=textValue(body.alertLabel,80)||"위협";
	const riskLevel=numberValue(body.riskLevel);
	const evidenceIndex=numberValue(body.evidenceIndex);
	const occurredAt=new Date(textValue(body.occurredAt,80));
	if(!eventId||riskLevel==null||!Number.isInteger(riskLevel)||riskLevel<1||riskLevel>4||evidenceIndex==null||Number.isNaN(occurredAt.getTime())){
		return null;
	}
	const rawReasons=Array.isArray(body.reasons)?body.reasons:[];
	const reasons=rawReasons
		.map(reason=>textValue(reason,240))
		.filter(reason=>reason.length>0)
		.slice(0,8);
	const rawLatitude=numberValue(body.latitude);
	const rawLongitude=numberValue(body.longitude);
	const latitude=rawLatitude!=null&&rawLatitude>=-90&&rawLatitude<=90?rawLatitude:null;
	const longitude=rawLongitude!=null&&rawLongitude>=-180&&rawLongitude<=180?rawLongitude:null;
	return{
		eventId,
		sessionId,
		category,
		alertLabel,
		riskLevel,
		evidenceIndex:Math.max(0,Math.min(100,evidenceIndex)),
		reasons,
		latitude,
		longitude,
		occurredAt
	};
}

export function normalizeDetections(value:unknown):CameraDetection[]{
	if(!Array.isArray(value)){
		return[];
	}
	const result:CameraDetection[]=[];
	for(const raw of value.slice(0,8)){
		if(raw==null||typeof raw!=="object"){
			continue;
		}
		const item=raw as Record<string,unknown>;
		if(item.label!=="knife"&&item.label!=="bottle"){
			continue;
		}
		const score=numberValue(item.score)??0;
		const rawBox=Array.isArray(item.box)?item.box:[];
		const box=rawBox.length===4
			?rawBox.map(numberValue).map(coordinate=>Math.max(0,Math.min(1,coordinate??0)))
			:[];
		result.push({
			label:item.label,
			displayLabel:item.label==="knife"?"칼":"병",
			score:Math.max(0,Math.min(1,score)),
			box
		});
	}
	return result;
}

function officerIdFromRequest(req:Request,getJwtSecret:()=>string):number|null{
	const sessionOfficerId=Number(req.session?.officerId);
	if(Number.isInteger(sessionOfficerId)&&sessionOfficerId>0){
		return sessionOfficerId;
	}
	const header=req.headers.authorization;
	if(!header?.startsWith("Bearer ")){
		return null;
	}
	try{
		const decoded=jwt.verify(header.slice(7),getJwtSecret())as UserTokenPayload;
		return Number.isInteger(decoded.officerId)&&decoded.officerId>0?decoded.officerId:null;
	}catch{
		return null;
	}
}

async function officerForRequest(req:Request,options:AiIntegrationOptions):Promise<Officer|null>{
	const officerId=officerIdFromRequest(req,options.getJwtSecret);
	if(officerId==null){
		return null;
	}
	let conn;
	try{
		conn=await getDBConnection();
		return await Officer.getCached(officerId,conn,options.appServer);
	}finally{
		conn?.release();
	}
}

async function requireOfficer(req:Request,res:Response,options:AiIntegrationOptions,admin=false):Promise<Officer|null>{
	const officer=await officerForRequest(req,options);
	if(officer==null){
		res.status(401).json({code:401,message:"Authentication required"});
		return null;
	}
	if(admin&&officer.role?.code!=="ADMIN"){
		res.status(403).json({code:403,message:"Administrator permission required"});
		return null;
	}
	return officer;
}

function isoValue(value:Date|string):string{
	const parsed=value instanceof Date?value:new Date(value);
	return Number.isNaN(parsed.getTime())?String(value):parsed.toISOString();
}

function threatPayload(row:ThreatRow,officer:Officer){
	let reasons:string[]=[];
	try{
		const parsed=JSON.parse(row.reasonsJson);
		reasons=Array.isArray(parsed)?parsed.map(String):[];
	}catch{}
	return{
		id:Number(row.id),
		eventId:row.eventId,
		sessionId:row.sessionId,
		officerId:officer.code,
		officerName:officer.name,
		rank:officer.rank,
		region:officer.region?.code??"",
		category:row.category,
		alertLabel:row.alertLabel,
		riskLevel:Number(row.riskLevel),
		evidenceIndex:Number(row.evidenceIndex),
		reasons,
		latitude:row.latitude==null?null:Number(row.latitude),
		longitude:row.longitude==null?null:Number(row.longitude),
		occurredAt:isoValue(row.occurredAt),
		createdAt:isoValue(row.createdAt)
	};
}

async function emitToAdmins(appServer:AppServer,event:string,payload:unknown):Promise<void>{
	// 기존 Role/Officer 연결 구조를 사용해 접속 중인 관리자에게만 전달합니다.
	const adminRole=await appServer.getAdminRole();
	if(adminRole==null){
		return;
	}
	for(const officer of adminRole.officers.values()){
		officer.emit(event,payload);
	}
}

function cameraPayload(stream:CameraStream){
	return{
		officerId:stream.officerId,
		officerName:stream.officerName,
		rank:stream.rank,
		region:stream.region,
		sessionId:stream.sessionId,
		updatedAt:stream.updatedAt,
		detections:stream.detections
	};
}

function pruneCameraStreams():void{
	// 원본 영상은 저장하지 않고 경찰관별 최신 프레임 한 장만 짧게 유지합니다.
	const now=Date.now();
	for(const[officerId,stream]of cameraStreams){
		if(now-stream.lastSeen>cameraStreamTimeoutMs){
			cameraStreams.delete(officerId);
		}
	}
}

export function registerAiIntegration(options:AiIntegrationOptions):void{
	const{app,appServer}=options;
	const jpegBody=express.raw({type:"image/jpeg",limit:"700kb"});

	app.get("/health",(_req,res)=>{
		res.json({status:"ok",service:"polapp-backend"});
	});

	app.post("/threat-alerts",async(req,res)=>{
		try{
			const officer=await requireOfficer(req,res,options);
			if(officer==null)return;
			const input=normalizeThreatInput(req.body);
			if(input==null){
				res.status(400).json({code:400,message:"Invalid threat alert payload"});
				return;
			}
			const latitude=input.latitude??(officer.x!==0?officer.x:null);
			const longitude=input.longitude??(officer.y!==0?officer.y:null);
			let conn;
			try{
				conn=await getDBConnection();
				const insertId=await conn.insert(`
					INSERT IGNORE INTO tblThreatAlert(
						eventId,officerId,sessionId,category,alertLabel,riskLevel,
						evidenceIndex,reasonsJson,latitude,longitude,occurredAt
					)VALUES(?,?,?,?,?,?,?,?,?,?,?);
				`,[
					input.eventId,officer.id,input.sessionId,input.category,input.alertLabel,
					input.riskLevel,input.evidenceIndex,JSON.stringify(input.reasons),
					latitude,longitude,input.occurredAt
				]);
				const rows=await conn.selectAll<ThreatRow>(
					"SELECT id,eventId,officerId,sessionId,category,alertLabel,riskLevel,evidenceIndex,reasonsJson,latitude,longitude,occurredAt,createdAt FROM tblThreatAlert WHERE eventId=? LIMIT 1;",
					[input.eventId]
				);
				if(rows.length===0){
					throw new Error("Threat alert was not found after insert");
				}
				const storedOfficer=await Officer.getCached(Number(rows[0].officerId),conn,appServer);
				if(storedOfficer==null){
					throw new Error("Threat alert officer was not found");
				}
				const payload=threatPayload(rows[0],storedOfficer);
				const created=insertId>0;
				if(created){
					await emitToAdmins(appServer,"threatDetected",payload);
				}
				res.status(created?201:200).json({code:0,result:payload,created});
			}finally{
				conn?.release();
			}
		}catch(error){
			console.error("[AI integration] POST /threat-alerts",error);
			if(!res.headersSent)res.status(500).json({code:500,message:"Server error"});
		}
	});

	app.get("/threat-alerts",async(req,res)=>{
		try{
			const admin=await requireOfficer(req,res,options,true);
			if(admin==null)return;
			const requestedLimit=Number(req.query.limit??50);
			const limit=Number.isFinite(requestedLimit)?Math.max(1,Math.min(200,Math.trunc(requestedLimit))):50;
			let conn;
			try{
				conn=await getDBConnection();
				const rows=await conn.selectAll<ThreatRow>(
					`SELECT id,eventId,officerId,sessionId,category,alertLabel,riskLevel,evidenceIndex,reasonsJson,latitude,longitude,occurredAt,createdAt
					 FROM tblThreatAlert ORDER BY createdAt DESC LIMIT ${limit};`,
					[]
				);
				const result=[];
				for(const row of rows){
					const officer=await Officer.getCached(Number(row.officerId),conn,appServer);
					if(officer!=null)result.push(threatPayload(row,officer));
				}
				res.json({code:0,result});
			}finally{
				conn?.release();
			}
		}catch(error){
			console.error("[AI integration] GET /threat-alerts",error);
			if(!res.headersSent)res.status(500).json({code:500,message:"Server error"});
		}
	});

	app.post("/camera-stream/status",async(req,res)=>{
		try{
			const officer=await requireOfficer(req,res,options);
			if(officer==null)return;
			const sessionId=textValue(req.body?.sessionId,120);
			if(!sessionId){
				res.status(400).json({code:400,message:"Camera session is required"});
				return;
			}
			const enabled=req.body?.enabled===true;
			let payload;
			let event;
			if(enabled){
				const previous=cameraStreams.get(officer.code);
				const sameSession=previous?.sessionId===sessionId;
				const stream:CameraStream={
					officerId:officer.code,
					officerName:officer.name,
					rank:officer.rank,
					region:officer.region?.code??"",
					sessionId,
					updatedAt:new Date().toISOString(),
					detections:sameSession?previous?.detections??[]:[],
					frame:sameSession?previous?.frame??null:null,
					lastSeen:Date.now()
				};
				cameraStreams.set(officer.code,stream);
				payload=cameraPayload(stream);
				event="cameraStreamUpdated";
			}else{
				cameraStreams.delete(officer.code);
				payload={officerId:officer.code,sessionId};
				event="cameraStreamStopped";
			}
			await emitToAdmins(appServer,event,payload);
			res.json({code:0,result:payload});
		}catch(error){
			console.error("[AI integration] POST /camera-stream/status",error);
			if(!res.headersSent)res.status(500).json({code:500,message:"Server error"});
		}
	});

	app.post("/camera-stream/frame",jpegBody,async(req,res)=>{
		try{
			const officer=await requireOfficer(req,res,options);
			if(officer==null)return;
			const sessionId=textValue(req.query.sessionId,120);
			const frame=Buffer.isBuffer(req.body)?req.body:null;
			if(!sessionId||frame==null||frame.length===0){
				res.status(400).json({code:400,message:"Camera frame and session are required"});
				return;
			}
			if(frame.length<4||frame[0]!==0xff||frame[1]!==0xd8){
				res.status(400).json({code:400,message:"JPEG frame is required"});
				return;
			}
			let rawDetections:unknown=[];
			try{
				rawDetections=JSON.parse(textValue(req.query.detections,10000)||"[]");
			}catch{}
			const stream:CameraStream={
				officerId:officer.code,
				officerName:officer.name,
				rank:officer.rank,
				region:officer.region?.code??"",
				sessionId,
				updatedAt:new Date().toISOString(),
				detections:normalizeDetections(rawDetections),
				frame,
				lastSeen:Date.now()
			};
			cameraStreams.set(officer.code,stream);
			const payload=cameraPayload(stream);
			await emitToAdmins(appServer,"cameraStreamUpdated",payload);
			res.status(202).json({code:0,result:payload});
		}catch(error){
			console.error("[AI integration] POST /camera-stream/frame",error);
			if(!res.headersSent)res.status(500).json({code:500,message:"Server error"});
		}
	});

	app.get("/camera-streams",async(req,res)=>{
		try{
			const admin=await requireOfficer(req,res,options,true);
			if(admin==null)return;
			pruneCameraStreams();
			const result=[...cameraStreams.values()]
				.filter(stream=>stream.frame!=null)
				.sort((a,b)=>b.updatedAt.localeCompare(a.updatedAt))
				.map(cameraPayload);
			res.json({code:0,result});
		}catch(error){
			console.error("[AI integration] GET /camera-streams",error);
			if(!res.headersSent)res.status(500).json({code:500,message:"Server error"});
		}
	});

	app.get("/camera-streams/:officerCode/frame",async(req,res)=>{
		try{
			const admin=await requireOfficer(req,res,options,true);
			if(admin==null)return;
			pruneCameraStreams();
			const frame=cameraStreams.get(req.params.officerCode)?.frame;
			if(frame==null){
				res.status(404).json({code:404,message:"Active camera frame not found"});
				return;
			}
			res.set({
				"Content-Type":"image/jpeg",
				"Cache-Control":"no-store, no-cache, must-revalidate, max-age=0",
				"Pragma":"no-cache"
			});
			res.send(frame);
		}catch(error){
			console.error("[AI integration] GET /camera-streams/:officerCode/frame",error);
			if(!res.headersSent)res.status(500).json({code:500,message:"Server error"});
		}
	});
}
