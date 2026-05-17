import jwt from"jsonwebtoken";
import{Server,Socket}from"socket.io";
import express,{Request,Response,Application}from"express";
import session,{Session,SessionData}from"express-session";
import Case,{GetOfficerIdsResultCode}from"./Case.js";
import User from"./User.js";
import Officer from"./Officer.js";
import AppServer,{getDBConnection}from"./AppServer.js";
import PendingMessage from"./PendingMessage.js";
import*as http from"node:http";
import*as readline from"node:readline";
import{getDateStr}from"./Utils.js";
declare module"http"{
	interface IncomingMessage{
		session:Session&Partial<SessionData>
	}
}
declare module"express-session"{
	interface SessionData{
		userId:number|null
	}
}
const app:Application=express();
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
	res.header("Access-Control-Allow-Methods","GET, POST, PUT, DELETE, OPTIONS");
	res.header("Access-Control-Allow-Headers","Content-Type");
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
		secure:false,
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
class Admin{
	static async create(userId:number){
	}
}
interface LoginRequestBody{
	officerId:string,
	matchingCode:string
}
app.post("/login",async(req:Request<{},{},LoginRequestBody>,res:Response)=>{
	const{officerId,matchingCode}=req.body;
	let conn
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
		const token=jwt.sign(
			{officerId:officer.id},
			process.env.jwtSecret||"0000",
			{expiresIn:"1h"}
		);
		res.status(200).json({
			status:"success",
			officerId:officer.code,
			token:token
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
interface AssignOfficerRequestBody{
	caseId:number,
	officerId:number
}
app.post("/case/assignOfficer",async(req:Request<{},{},AssignOfficerRequestBody>,res:Response)=>{
	const{caseId,officerId}=req.body;
	const updatedBy=req.session?.userId;
	if(updatedBy==null){
		res.json({
			code:-1
		});
		return;
	}
	let conn;
	try{
		conn=await getDBConnection();
		let _case=await Case.getCached(caseId,conn);
		if(_case==null){
			res.json({code:-2});
			return;
		}
		const result=await _case.assignOfficer(officerId,updatedBy,conn);
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
interface CreateCaseRequestBody{
	name:string
}
app.post("/case",async(req:Request<{},{},CreateCaseRequestBody>,res:Response)=>{
	const{name}=req.body;
	if(name==null||name.length==0){
		res.json({code:-1});
		return;
	}
	const createdBy=req.session?.userId;
	if(createdBy==null){
		res.json({code:-2});
		return;
	}
	let conn;
	try{
		conn=await getDBConnection();
		const _case=await Case.create(name,createdBy,conn);
		if(_case==null){
			res.json({code:-3});
			return;
		}
		res.json({
			code:0,
			caseId:_case.id
		});
	}catch(e){
		console.error(e);
		res.json({code:-4});
	}finally{
		conn?.release();
	}
});
app.put("/case/:id/setComplete",async(req:Request,res:Response)=>{
	const{id}=req.params;
	const updatedBy=req.session?.userId;
	if(updatedBy==null){
		res.json({
			code:-1
		});
		return;
	}
	let conn;
	try{
		conn=await getDBConnection();
		const _case=await Case.getCached(Number(id),conn);
		if(_case==null){
			res.json({
				code:-2
			});
			return;
		}
		const result=await _case.setComplete(updatedBy,conn);
		res.json({
			code:0,
			result:result
		});
	}catch(e){
		console.error(e);
		res.json({
			code:-2
		});
	}finally{
		conn?.release();
	}
});
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
	const createdBy=req.session?.userId;
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
interface UserLoginRequestBody{
	email:string,
	passwd:string
}
app.post("/user/login",async(req:Request<{},{},UserLoginRequestBody>,res:Response)=>{
	const{email,passwd}=req.body;
	if(email==null||email.length==0){
		res.json({
			code:-1
		});
		return;
	}
	if(passwd==null||passwd.length==0){
		res.json({
			code:-2
		});
		return;
	}
	let conn;
	try{
		conn=await getDBConnection();
		const result=await User.login(conn,email,passwd);
		if(result.code==0){
			req.session.userId=result.userId;
		}
		res.json({
			code:0,
			result:result
		});
	}catch(e){
		res.json({
			code:-3
		});
	}finally{
		conn?.release();
	}
});
interface DeleteUserParams{
	id:number
}
app.delete("/user/:id",async(req:Request<DeleteUserParams>,res:Response)=>{
	const{id}=req.params;
	const createdBy=req.session?.userId;
	if(createdBy==null){
		res.json({
			code:-1
		});
		return;
	}
	let conn;
	try{
		conn=await getDBConnection();
		const result=await User.remove(conn,id,createdBy);
		res.json({
			code:0,
			result:result
		});
	}catch(ex){
		console.error(ex);
		res.json({code:-2});
	}finally{
		conn?.release();
	}
});
interface CreateOfficerRequestBody{
	userId:number,
	code:string
}
app.post("/officer",async(req:Request<{},{},CreateOfficerRequestBody>,res:Response)=>{
	const{userId,code}=req.body;
	const createdBy=req.session?.userId;
	if(createdBy==null){
		res.json({
			code:-1
		});
		return;
	}
	let conn;
	try{
		conn=await getDBConnection();
		const result=await Officer.create(conn,userId,code,createdBy,appServer);
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
	const updatedBy=req.session?.userId;
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
	const session=socket.request.session;
	console.log(`[${getDateStr()}] Connected`);
	let officer:Officer|null=null;
	socket.on("join",async({officerId,region,role})=>{
		console.log(`[${getDateStr()}] [socket.on join] officerId=${officerId},region=${region},role=${role}`);
		officer=await appServer.setOfficerJoined(officerId,region,role,socket);
		if(officer==null){
			console.log(`[${getDateStr()}] socket.on join Failed. officerId=${officerId},region=${region},role=${role}`);
		}
	});
	socket.on("sendMyLocation",({officerId,region,latitude,longitude})=>{
		if(officer==null){
			console.log(`[socket.on sendMyLocation] officer=null`);
			socket.disconnect();
			return;
		}
		if(officer.region==null){
			return;
		}
		officer.updateLocation(latitude,longitude);
		appServer.setOfficerLocationUpdated(officer);
	});
	socket.on("sendRadioMessage",async({officerId,region,message,timestamp})=>{
		if(officer==null){
			console.log(`[socket.on sendRadioMessage] officer=null`);
			socket.disconnect();
			return;
		}
		await appServer.pushPendingMessage(officer,region,message,timestamp);
	});
	socket.on("disconnect",(reason:string)=>{
		console.log(`[${getDateStr()}] [socket.on disconnect]`);
		if(officer==null){
			socket.disconnect();
			return;
		}
		officer.removeSocket(socket);
	});
});
httpServer.listen(port,()=>{
	console.log(`Listening on port=${port}`);
});
