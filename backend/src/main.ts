import{Server,Socket}from"socket.io";
import express,{Request,Response,Application}from"express";
import session,{Session,SessionData}from"express-session";
import Case,{GetOfficerIdsResultCode}from"./Case.js";
import User from"./User.js";
import Police from"./Police.js";
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
	secret:process.env.sessionSecret,
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
	const assignResult=await Case.assignPolice(caseId,policeId,updatedBy);
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
	const setCaseCompleteResult=await Case.setComplete(caseId,updatedBy);
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
	const userCreateResult=await User.create(email,passwd,createdBy,name);
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
	const loginResult=await User.login(email,passwd);
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
	const deleteUserResult=await User.remove(userId,createdBy);
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
	const createPoliceResult=await Police.create(userId,officerId,createdBy);
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
	const removePoliceResult=await Police.remove(policeId,updatedBy);
	res.json({
		code:0,
		result:removePoliceResult
	});
});
const sockets=new Map<string,Socket>();
let port=8080;
let lastPositionSyncTime=0;
const updatedPolices=new Map<number,number>();
const policeClients=new Map<number,PoliceClient>();
function setOfficerUpdated(policeId:number,x:number,y:number){
	const policeClient=policeClients.get(policeId);
	if(policeClient==null){
		return;
	}
	policeClient.x=x;
	policeClient.y=y;
	updatedPolices.set(policeId,1);
}
class PoliceClient{
	sockets:Map<string,Socket>;
	x:number;
	y:number;
	officerId:string;
	policeId:number;
	constructor(policeId:number,officerId:string){
		this.x=0;
		this.y=0;
		this.policeId=policeId;
		this.officerId=officerId;
		this.sockets=new Map<string,Socket>();
	}
	addSocket(socket:Socket){
		this.sockets.set(socket.id,socket);
	}
	removeSocket(socketId:string){
		this.sockets.delete(socketId);
		return this.sockets.size==0;
	}
	syncPeerPosition(officerId:string,x:number,y:number){
		for(const socket of this.sockets.values()){
			socket.emit("updateColleagueLocation",{
				officerId,
				latitude:x,
				longitude:y
			});
		}
	}
}
async function syncOfficerPositions(){
	const updatedPoliceIds=updatedPolices.keys();
	for(const policeId of updatedPoliceIds){
		const police=policeClients.get(policeId);
		if(police==null){
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
		const policeIds=policeClients.keys();
		for(const _policeId of policeIds){
			if(_policeId===policeId){
				continue;
			}
			const peerClient=policeClients.get(_policeId);
			if(peerClient==null){
				console.log("syncOfficerPositions peerClient=null");
				continue;
			}
			peerClient.syncPeerPosition(police.officerId,police.x,police.y);
		}
	}
	updatedPolices.clear();
}
async function loop(){
	while(true){
		await syncOfficerPositions();
		await new Promise(function(resolve){
			setTimeout(resolve,100);
		});
	}
}
function removePoliceSocket(policeId:number,socketId:string){
	const policeClient=policeClients.get(policeId);
	if(policeClient==null){
		return;
	}
	const offline=policeClient.removeSocket(socketId);
	if(offline){
		policeClients.delete(policeId);
	}
}
io.on("connection",(socket:Socket)=>{
	const session=socket.request.session;
	console.log("Connected");
	let socketPoliceId:number|null=null;
	socket.on("join",async({officerId})=>{
		console.log("join officerId="+officerId);
		const getPoliceIdResult=await Police.getPoliceId(officerId);
		if(getPoliceIdResult.code!=0){
			console.log("getPoliceIdResult.code="+getPoliceIdResult.code);
			return;
		}
		socketPoliceId=getPoliceIdResult.policeId;
		if(socketPoliceId==null){
			return;
		}
		let policeClient=policeClients.get(socketPoliceId);
		if(policeClient==null){
			policeClient=new PoliceClient(socketPoliceId,officerId);
			policeClients.set(socketPoliceId,policeClient);
		}
		policeClient.addSocket(socket);
	});
	socket.on("sendMyLocation",({officerId,latitude,longitude})=>{
		if(socketPoliceId==null){
			return;
		}
		setOfficerUpdated(socketPoliceId,latitude,longitude);
	});
	socket.on("disconnect",(reason:string)=>{
		console.log("disconnected");
		if(socketPoliceId==null){
			return;
		}
		removePoliceSocket(socketPoliceId,socket.id);
	});
});
httpServer.listen(port,()=>{
	console.log("Listening on port="+port);
});
loop();
