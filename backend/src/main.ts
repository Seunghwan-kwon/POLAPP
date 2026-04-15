import{Server,Socket}from"socket.io";
import express,{Request,Response,Application}from"express";
import session,{Session,SessionData}from"express-session";
import Case,{GetOfficerIdsResultCode}from"./Case.js";
import User from"./User.js";
import Police from"./Police.js";
import OfficerClient from"./OfficerClient.js";
import AppServer,{getDBConnection}from"./AppServer.js";
import*as http from"http";
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
interface AssignPoliceRequestBody{
	caseId:number,
	policeId:number
}
app.post("/case/assignPolice",async(req:Request<{},{},AssignPoliceRequestBody>,res:Response)=>{
	const{caseId,policeId}=req.body;
	const updatedBy=req.session?.userId;
	if(updatedBy==null){
		res.json({
			code:-1
		});
		return;
	}
	const conn=await getDBConnection();
	const assignResult=await Case.assignPolice(conn,caseId,policeId,updatedBy);
	res.json({
		code:0,
		result:assignResult
	});
});
app.post("/case",async(req:Request,res:Response)=>{
	const{caseName}=req.body;
	const caseCreateResult=await Case.create(caseName);
	res.json({
		code:0,
		result:caseCreateResult
	});
});
app.post("/case/setComplete",async(req:Request,res:Response)=>{
	const{caseId}=req.body;
	const updatedBy=req.session?.userId;
	if(updatedBy==null){
		res.json({
			code:-1
		});
		return;
	}
	const conn=await getDBConnection();
	const setCaseCompleteResult=await Case.setComplete(conn,caseId,updatedBy);
	res.json({
		code:0,
		result:setCaseCompleteResult
	});
});
interface CreateUserRequestBody{
	email:string,
	passwd:string,
	name:string
}
app.post("/user",async(req:Request<{},{},CreateUserRequestBody>,res:Response)=>{
	const{email,passwd,name}=req.body;
	const createdBy=req.session?.userId;
	if(createdBy==null){
		res.json({
			code:-1
		});
		return;
	}
	const conn=await getDBConnection();
	const userCreateResult=await User.create(conn,email,passwd,createdBy,name);
	res.json({
		code:0,
		result:userCreateResult
	});
});
interface UserLoginRequestBody{
	email:string,
	passwd:string
}
app.post("/user/login",async(req:Request<{},{},UserLoginRequestBody>,res:Response)=>{
	const{email,passwd}=req.body;
	if(email==null||passwd==null){
		res.json({
			code:-1
		});
		return;
	}
	const conn=await getDBConnection();
	const loginResult=await User.login(conn,email,passwd);
	if(loginResult.code==0){
		req.session.userId=loginResult.userId;
	}
	res.json({
		code:0,
		result:loginResult
	});
});
interface DeleteUserParams{
	userId:number
}
app.delete("/user/:userId",async(req:Request<DeleteUserParams>,res:Response)=>{
	const{userId}=req.params;
	const createdBy=req.session?.userId;
	if(createdBy==null){
		res.json({
			code:-1
		});
		return;
	}
	const conn=await getDBConnection();
	const deleteUserResult=await User.remove(conn,userId,createdBy);
	res.json({
		code:0,
		result:deleteUserResult
	});
});
interface CreatePoliceRequestBody{
	userId:number,
	officerId:string
}
app.post("/police",async(req:Request<{},{},CreatePoliceRequestBody>,res:Response)=>{
	const{userId,officerId}=req.body;
	const createdBy=req.session?.userId;
	if(createdBy==null){
		res.json({
			code:-1
		});
		return;
	}
	const conn=await getDBConnection();
	const createPoliceResult=await Police.create(conn,userId,officerId,createdBy);
	res.json({
		code:0,
		result:createPoliceResult
	});
});
interface DeletePoliceParams{
	policeId:number;
}
app.delete("/police/:policeId",async(req:Request<DeletePoliceParams>,res:Response)=>{
	const{policeId}=req.params;
	const updatedBy=req.session?.userId;
	if(updatedBy==null){
		res.json({
			code:-1
		});
		return;
	}
	const conn=await getDBConnection();
	const removePoliceResult=await Police.remove(conn,policeId,updatedBy);
	res.json({
		code:0,
		result:removePoliceResult
	});
});
let port=8080;
const appServer=new AppServer();
io.on("connection",(socket:Socket)=>{
	const session=socket.request.session;
	console.log("Connected");
	let officerClient:OfficerClient|null=null;
	socket.on("join",async({officerId,region})=>{
		console.log("join officerId="+officerId+",region="+region);
		officerClient=await appServer.setOfficerJoined(officerId,region,socket);
	});
	socket.on("sendMyLocation",({officerId,latitude,longitude})=>{
		if(officerClient==null){
			console.log("sendMyLocation officerClient=null");
			return;
		}
		officerClient.setLocationUpdated(latitude,longitude);
	});
	socket.on("sendRadioMessage",({officerId,region,message,timestamp})=>{
		if(officerClient==null){
			console.log("[socket.sendRadioMessageHandler] officerClient=null");
			return;
		}
		officerClient.pushRadioMessage(message,timestamp);
	});
	socket.on("disconnect",(reason:string)=>{
		console.log("socket.disconnect");
		if(officerClient==null){
			return;
		}
		officerClient.removeSocket(socket.id);
	});
});
appServer.loop();
httpServer.listen(port,()=>{
	console.log("Listening on port="+port);
});
