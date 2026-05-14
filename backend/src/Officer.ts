import{Socket}from"socket.io";
import DBConnection from"./DBConnection.js";
import Case from"./Case.js";
import PendingMessage from"./PendingMessage.js";
import Region from"./Region.js";
import Role from"./Role.js";
enum RemoveResultCode{
	Success=0,
	Exception1=-1,
	DBConnFailed=-3,
	UpdateFailed=-4
}
class RemoveResult{
	code:RemoveResultCode;
	constructor(code:RemoveResultCode){
		this.code=code;
	}
}
enum CreateResultCode{
	Success=0,
	Exception1=-1,
	DBConnFailed=-3,
	InsertFailed=-4,
	Duplicate=-5
}
class CreateResult{
	code:CreateResultCode;
	officer:Officer|null;
	constructor(code:CreateResultCode,officer:Officer|null){
		this.code=code;
		this.officer=officer;
	}
}
enum GetCaseResultCode{
	Success=0,
	Error=-1
}
class GetCaseResult{
	code:GetCaseResultCode;
	_case:Case|null;
	constructor(code:GetCaseResultCode,_case:Case|null){
		this.code=code;
		this._case=_case;
	}
}
enum FindResultCode{
	Success=0,
	Error=-1
}
class FindResult{
	code:number;
	officer:Officer|null;
	constructor(code:FindResultCode,officer:Officer|null){
		this.code=code;
		this.officer=officer;
	}
}
export default class Officer{
	id:number;
	code:string;
	x:number;
	y:number;
	region:Region|null;
	role:Role|null;
	sockets:Map<string,Socket>
	conn:DBConnection;
	constructor(id:number,conn:DBConnection){
		this.id=id;
		this.x=0;
		this.y=0;
		this.region=null;
		this.role=null;
		this.code="(unknown)";
		this.sockets=new Map<string,Socket>();
		this.conn=conn;
	}
	static cached=new Map<number,Officer|null>();
	static async getCached(id:number,conn:DBConnection):Promise<Officer|null>{
		let officer=Officer.cached.get(id);
		if(officer===undefined){
			const row=await conn.selectRow<any>(
				"select id from tblOfficer where id=? limit 1;",
				[id]
			);
			if(row==null){
				Officer.cached.set(id,null);
				return null;
			}
			officer=new Officer(id,conn);
			Officer.cached.set(id,officer);
		}
		return officer;
	}
	static async findByCode(conn:DBConnection,code:string):Promise<FindResult>{
		try{
			const id=await conn.selectSingle<number>(
				"select id from tblOfficer where code=? limit 1;",
				[code]
			);
			if(id==null){
				return new FindResult(FindResultCode.Success,null);
			}
			const officer=new Officer(id,conn);
			officer.code=code;
			return new FindResult(FindResultCode.Success,officer);
		}catch(err:any){
			console.error(err);
			return new FindResult(FindResultCode.Error,null);
		}finally{
			conn?.release();
		}
	}
	async getCase():Promise<GetCaseResult>{
		try{
			const caseId=await this.conn.selectSingle<number>(
				"select caseId from tblOfficerCase where officerId=? limit 1;",
				[this.id]
			);
			if(caseId==null){
				return new GetCaseResult(
					GetCaseResultCode.Success,
					null
				);
			}
			const _case=await Case.getCached(caseId,this.conn);
			return new GetCaseResult(
				GetCaseResultCode.Success,
				_case
			);
		}catch(err:any){
			return new GetCaseResult(
				GetCaseResultCode.Error,
				null
			);
		}finally{
		}
	}
	static async create(conn:DBConnection,id:number,code:string,createdBy:number):Promise<CreateResult>{
		try{
			await conn.beginTransaction();
			const insertId=await conn.insert(
				"insert into tblOfficer(userId,officerId,createdBy)values(?,?,?);",
				[id,code,createdBy]
			);
			if(insertId==null){
				await conn.rollback();
				return new CreateResult(
					CreateResultCode.InsertFailed,
					null
				);
			}
			await conn.commit();
			const officer=new Officer(insertId,conn);
			officer.code=code;
			Officer.cached.set(officer.id,officer);
			return new CreateResult(0,officer);
		}catch(err:any){
			try{
				await conn?.rollback();
			}catch{}
			if(err?.code==="ER_DUP_ENTRY"){
				return new CreateResult(
					CreateResultCode.Duplicate,
					null
				);
			}
			return new CreateResult(
				CreateResultCode.Exception1,
				null
			);
		}finally{
		}
	}
	async remove(updatedBy:number):Promise<RemoveResult>{
		try{
			await this.conn.beginTransaction();
			const changedCount=await this.conn.update(
				"update tblOfficer set isActive=0 where id=? and isActive=1 limit 1;",
				[this.id]
			);
			if(changedCount!==1){
				await this.conn.rollback();
				return new RemoveResult(
					RemoveResultCode.UpdateFailed
				);
			}
			await this.conn.commit();
			return new RemoveResult(
				RemoveResultCode.Success
			);
		}catch(ex1){
			try{
				await this.conn?.rollback();
			}catch{}
			return new RemoveResult(
				RemoveResultCode.Exception1
			);
		}finally{
		}
	}
	isOffline():boolean{
		return this.sockets.size==0;
	}
	addSocket(socket:Socket):void{
		this.sockets.set(socket.id,socket);
	}
	removeSocket(socket:Socket):void{
		this.sockets.delete(socket.id);
		if(this.isOffline()){
			if(this.region){
				this.region.removeOfficer(this);
				this.region=null;
			}
			if(this.role){
				this.role.removeOfficer(this);
				this.role=null;
			}
		}
	}
	syncPeerLocation(peer:Officer):number{
		const payload={
			officerId:peer.code,
			latitude:peer.x,
			longitude:peer.y
		};
		let result=0;
		for(const socket of this.sockets.values()){
			socket.emit("updateColleagueLocation",payload);
			result++;
		}
		return result;
	}
	syncPeerMessage(message:PendingMessage):number{
		const peer=message.sender;
		const region=peer.region;
		if(region==null){
			return-1;
		}
		const payload={
			officerId:peer.code,
			region:region.code,
			message:message.content,
			timestamp:message.timestamp
		};
		let result=0;
		for(const socket of this.sockets.values()){
			socket.emit("receiveRadioMessage",payload);
			result++;
		}
		return result;
	}
	setRole(role:Role):number{
		if(this.role!=null){
			if(this.role==role){
				return 1;
			}else{
				this.role.removeOfficer(this);
			}
		}
		role.addOfficer(this);
		this.role=role;
		console.log(`[Officer.setRole] officer.code=${this.code} role.code=${role.code}`);
		return 0;
	}
	setRegion(region:Region):number{
		if(this.region!=null){
			if(this.region==region){
				return 1;
			}else{
				this.region.removeOfficer(this);
			}
		}
		region.addOfficer(this);
		this.region=region;
		console.log(`[Officer.setRegion] officer.code=${this.code} region.code=${region.code}`);
		return 0;
	}
	updateLocation(x:number,y:number):void{
		this.x=x;
		this.y=y;
	}
}
