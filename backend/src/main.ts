import jwt,{JwtPayload}from"jsonwebtoken";
import{Server,Socket}from"socket.io";
import express,{Request,Response,Application}from"express";
import session,{Session,SessionData}from"express-session";
import Report from"./Report.js";
import Region from"./Region.js";
import Role from"./Role.js";
import User from"./User.js";
import Officer from"./Officer.js";
import AppServer,{getDBConnection}from"./AppServer.js";
import PendingMessage from"./PendingMessage.js";
import*as http from"node:http";
import*as fs from"node:fs";
//import*as readline from"node:readline";
import{getDateStr}from"./Utils.js";
declare module"http"{
	interface IncomingMessage{
		session:Session&Partial<SessionData>
	}
}
declare module"express-session"{
	interface SessionData{
		officerId:number|null
	}
}
const app:Application=express();
let startTime=new Date();
let buildTime=new Date();
app.set("trust proxy",1);
app.use(express.static("public"));
app.use(express.json());
function getPortPrefix(){
	return (Number(process.env.portPrefix)||0);
}
app.use((req,res,next)=>{
	const origin=req.headers.origin;
	const domain=process.env.domain||"localhost";
	const portPrefix=getPortPrefix();
	/*
	const allowedOrigins=[];
	allowedOrigins.push(`http://${domain}:${portPrefix+80}`);
	*/
	//if(origin&&allowedOrigins.includes(origin)){
		res.header("Access-Control-Allow-Origin",origin);
	//}
	res.header("Access-Control-Allow-Credentials","true");
	res.header("Access-Control-Allow-Methods","GET, POST, PUT, DELETE, OPTIONS, PATCH");
	res.header("Access-Control-Allow-Headers","Content-Type, Authorization");
	if(req.method==="OPTIONS"){
		return res.sendStatus(200);
	}
	next();
});
const sessionMiddleware=session({
	secret:process.env.sessionSecret||"s2e3cr1et",
	resave:false,
	saveUninitialized:false,
	cookie:{
		httpOnly:true,
		secure:true,
		sameSite:"none",
		maxAge:1000*3600
	}
});
app.use(sessionMiddleware);
const httpServer=http.createServer(app);
interface ClientToServerEvents{
}
interface ServerToClientEvents{
}
const io=new Server<ClientToServerEvents,ServerToClientEvents>(httpServer);
io.engine.use(sessionMiddleware);
interface LoginRequestBody{
	officerId:string,
	matchingCode:string
}
app.get("/info",(req:Request,res:Response)=>{
	res.json({startTime:getDateStr(startTime),buildTime:getDateStr(buildTime)});
});
app.post("/login",async(req:Request<{},{},LoginRequestBody>,res:Response)=>{
	const{officerId,matchingCode}=req.body;
	console.log(`[${getDateStr()}] /login officerId=${officerId},matchingCode=${matchingCode}`);
	if(officerId==null){
		res.json({code:-1});
		return;
	}
	if(matchingCode==null){
		res.json({code:-2});
		return;
	}
	let conn;
	try{
		conn=await getDBConnection();
		const officer=await Officer.findByCode(conn,officerId,appServer);
		const failPayload={
			status:"fail",
			message:"사번 또는 코드가 일치하지 않습니다."
		};
		if(!officer){
			res.status(401).json(failPayload);
			return;
		}
		const officerMatchingCode=await officer.getMatchingCode(conn);
		if(officerMatchingCode!==matchingCode){
			res.status(401).json(failPayload);
			return;
		}
		const payload={
			officerId:officer.id
		};
		const token=jwt.sign(
			payload,
			getJwtSecret(),
			{expiresIn:"1h"}
		);
		req.session.officerId=officer.id;
		res.status(200).json({
			status:"success",
			officerId:officer.code,
			token:token,
			name:officer.name,
			rank:officer.rank,
			region:officer.region?.code,
			affiliaton:officer.affiliation
		});
	}catch(e){
		console.error(e);
		res.status(500).json({
			status:"fail",
			message:"서버 오류입니다."
		});
	}finally{
		conn?.release();
	}
});
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
function getJwtSecret(){
	return process.env.jwtSecret||"0000";
}
interface UserTokenPayload extends JwtPayload{
	officerId:number;
}
function authByHeader(authHeader:string|null):number{
	if(authHeader==null){
		return-1;
	}
	if(!authHeader.startsWith("Bearer ")){
		return-2;
	}
	const token=authHeader.split(" ")[1];
	try{
		const decoded=jwt.verify(token,getJwtSecret())as UserTokenPayload;
		return decoded.officerId;
	}catch(e){
		console.error(e);
		return-3;
	}
}
interface GetReportsQuery{
	status:string|null
}
app.get("/reports",async(req:Request<{},{},{},GetReportsQuery>,res:Response)=>{
	let{status}=req.query;
	const authHeader=req.headers.authorization;
	let requestedBy=req.session?.officerId;
	console.log(`[${getDateStr()}] GET /reports requestedBy=${requestedBy},status=${status}`);
	let authType=-1;
	if(requestedBy==null){
		requestedBy=authByHeader(authHeader||null);
		if(requestedBy<0){
			res.json({code:-1});
			return;
		}else if(requestedBy==null){
			res.json({code:-2});
			return;
		}
		authType=2;
	}else{
		authType=1;
	}
	let conn;
	try{
		conn=await getDBConnection();
		const ids=await Report.select(conn,status);
		if(ids==null){
			res.json({code:-2});
			return;
		}
		const reports=[];
		for(const id of ids){
			const report=await Report.getCached(id,conn);
			reports.push(report);
		}
		res.json({
			code:0,
			authType,
			result:reports
		});
	}catch(e){
		console.error(e);
		res.json({code:-3});
	}finally{
		conn?.release();
	}
});
interface PatchReportParams{
	reportId:string
}
app.patch("/reports/:reportId/close",async(req:Request<PatchReportParams>,res:Response)=>{
	let{reportId}=req.params;
	const closedBy=req.session?.officerId;
	console.log(`[${getDateStr()}] PATCH /reports/${reportId}/close closedBy=${closedBy}`);
	if(closedBy==null){
		res.json({
			code:-1
		});
		return;
	}
	let conn;
	try{
		conn=await getDBConnection();
		const splitted=reportId.split("-");
		let id=0;
		if(splitted.length==2){
			id=Number(splitted[1]);
		}else{
			id=Number(reportId);
		}
		const report=await Report.getCached(id,conn);
		if(report==null){
			res.json({code:-2});
			return;
		}
		const result=await report.close(closedBy,conn);
		appServer.broadcast("reportClosed",report);
		res.json({
			code:0,
			result:{
				id:report.id,
				status:"CLOSED",
				closedAt:report.closedAt,
				closedBy:report.closedBy
			}
		});
	}catch(e){
		console.error(e);
		res.json({code:-3});
	}finally{
		conn?.release();
	}
});
interface CreateReportRequestBody{
	title:string,
	description:string,
	status:string|null,
	severity:string,
	latitude:number,
	longitude:number
}
app.post("/reports",async(req:Request<{},{},CreateReportRequestBody>,res:Response)=>{
	const{title,description,severity,status,latitude,longitude}=req.body;
	const createdBy=req.session?.officerId;
	console.log(`[${getDateStr()}] POST /reports createdBy=${createdBy},title=${title}`);
	if(createdBy==null){
		res.json({
			code:-1
		});
		return;
	}
	let conn;
	try{
		conn=await getDBConnection();
		const creator=await Officer.getCached(createdBy,conn,appServer);
		if(creator==null){
			res.json({code:-2});
			return;
		}
		const report=await Report.create(
			title,description,
			severity,latitude,longitude,
			status,createdBy,new Date(),
			null,null,
			conn
		);
		appServer.broadcast("reportCreated",report);
		res.json({
			code:0,
			result:report
		});
	}catch(e){
		console.error(e);
		res.json({code:-2});
	}finally{
		conn?.release();
	}
});
interface CreateOfficerRequestBody{
	userId:number,
	code:string,
	name:string,
	rank:string,
	regionId:number,
	roleId:number,
	affiliation:string
}
app.post("/officer",async(req:Request<{},{},CreateOfficerRequestBody>,res:Response)=>{
	const{userId,code,name,rank,regionId,roleId,affiliation}=req.body;
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
		const region=await Region.getCached(regionId,conn);
		const role=await Role.getCached(roleId,conn);
		const result=await Officer.create(conn,userId,code,name,rank,region,role,affiliation,createdBy,appServer);
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
interface DeleteOfficerParams{
	id:number;
}
app.delete("/officer/:id",async(req:Request<DeleteOfficerParams>,res:Response)=>{
	const{id}=req.params;
	const updatedBy=req.session?.officerId;
	if(updatedBy==null){
		res.json({
			code:-1
		});
		return;
	}
	let conn;
	try{
		conn=await getDBConnection();
		let officer=await Officer.getCached(id,conn,appServer);
		if(officer==null){
			res.json({code:-2});
			return;
		}
		const result=await officer.remove(updatedBy,conn);
		res.json({
			code:0,
			result:result
		});
	}catch(e){
		console.error(e);
		res.json({code:-3});
	}finally{
		conn?.release();
	}
});
const port=getPortPrefix()+80;
const appServer=new AppServer();
console.log("port="+port);
io.on("connection",(socket:Socket)=>{
	const forwarded=socket.handshake.headers["x-forwarded-for"];
	let ipAddress:string;
	if(forwarded){
		const ipList=Array.isArray(forwarded)?forwarded[0]:forwarded;
		ipAddress=ipList.split(",")[0].trim();
	}else{
		ipAddress=socket.handshake.address;
	}
	const session=socket.request.session;
	console.log(`[${getDateStr()}] [io.on connection] socket.id=${socket.id},ip=${ipAddress}`);
	let officer:Officer|null=null;
	socket.on("join",async({officerId})=>{
		officer=await appServer.setOfficerJoined(officerId,socket);
		if(officer==null){
			console.log(`[${getDateStr()}] [socket.on join]  officerId=${officerId},officer=null Rejected.`);
		}
		console.log(`[${getDateStr()}] [socket.on join] officerId=${officerId},socket.id=${socket.id} Accepted.`);
	});
	socket.on("sendMyLocation",({/*officerId,region,*/latitude,longitude})=>{
		if(officer==null){
			console.log(`[${getDateStr()}] [socket.on sendMyLocation] socket.id=${socket.id},officer=null Rejected.`);
			socket.disconnect();
			return;
		}
		if(officer.region==null){
			console.log(`[${getDateStr()}] [socket.on sendMyLocation] socket.id=${socket.id},officer.code=${officer.code},officer.region=null Rejected.`);
			return;
		}
		//console.log(`[${getDateStr()}] [socket.on sendMyLocation] socket.id=${socket.id},officer.code=${officer.code},region=${officer.region.code}`);
		officer.setLocation(latitude,longitude);
		appServer.setOfficerLocationUpdated(officer);
	});
	socket.on("sendRadioMessage",async({/*officerId,*/region,message,timestamp})=>{
		if(officer==null){
			console.log(`[${getDateStr()}] [socket.on sendRadioMessage] socket.id=${socket.id},officer=null Rejected.`);
			socket.disconnect();
			return;
		}
		console.log(`[${getDateStr()}] [socket.on sendRadioMessage] socket.id=${socket.id},officer.code=${officer.code} Accepted.`);
		await appServer.pushPendingMessage(officer,region,message,timestamp);
	});
	socket.on("disconnect",(reason:string)=>{
		if(officer==null){
			console.log(`[${getDateStr()}] [socket.on disconnect] socket.id=${socket.id},officer=null`);
			return;
		}
		console.log(`[${getDateStr()}] [socket.on disconnect] socket.id=${socket.id},officer.code=${officer.code} Accepted`);
		officer.removeSocket(socket);
	});
});
function getBuildTime(){
	const stats=fs.statSync(__filename);
	const createdDate=stats.mtime;
	return createdDate;
}
httpServer.listen(port,()=>{
	startTime=new Date();
	buildTime=getBuildTime();
	console.log(`Listening on port=${port}`);
});
