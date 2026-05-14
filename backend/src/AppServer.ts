import{Socket}from"socket.io";
import Officer from"./Officer.js";
import PendingMessage from"./PendingMessage.js";
import DBConnection from"./DBConnection.js";
import Region from"./Region.js";
import Role from"./Role.js";
import{getMySqlConnection}from"./MySqlConnection.js";
enum DBType{
	MySQL,
	Sqlite3
}
const dbType=DBType.MySQL;
export async function getDBConnection(){
	if(dbType==DBType.MySQL){
		const conn=await getMySqlConnection();
		return conn;
	}else if(dbType==DBType.Sqlite3){
		return new DBConnection();
	}else{
		return new DBConnection();
	}
}
export default class AppServer{
	updatedOfficers:Map<number,Officer>;
	officers:Map<number,Officer>;
	pendingMessages:Array<PendingMessage>;
	adminRole:Role|null;
	constructor(){
		this.updatedOfficers=new Map<number,Officer>();
		this.officers=new Map<number,Officer>();
		this.pendingMessages=new Array<PendingMessage>();
		this.adminRole=null;
	}
	async getAdminRole():Promise<Role|null>{
		if(this.adminRole==null){
			try{
				const conn=await getDBConnection();
				const role=await Role.findByCode("ADMIN",conn);
				this.adminRole=role;
			}catch(ex){
				console.error(ex);
				return null;
			}
		}
		return this.adminRole;
	}
	async syncOfficerLocations(){
		const updatedOfficers=this.updatedOfficers.values();
		for(const officer of updatedOfficers){
			const region=officer.region;
			if(region==null){
				continue;
			}
			let peers=region.officers.values();
			for(const peer of peers){
				if(peer==officer){
					continue;
				}
				peer.syncPeerLocation(officer);
			}
			const adminRole=await this.getAdminRole();
			if(adminRole!=null){
				peers=adminRole.officers.values();
				for(const peer of peers){
					if(peer==officer){
						continue;
					}
					peer.syncPeerLocation(officer);
				}
			}
		}
		this.updatedOfficers.clear();
	}
	broadcastOfficerMessages(){
		for(const pendingMessage of this.pendingMessages){
			const sender=pendingMessage.sender;
			const region=sender.region;
			if(region==null){
				console.log("[broadcaseOfficerMessages] region==null");
				continue;
			}
			const peers=region.officers.values();
			for(const peer of peers){
				if(peer==sender){
					continue;
				}
				peer.syncPeerMessage(pendingMessage);
			}
		}
		this.pendingMessages.length=0;
	}
	async setOfficerJoined(officerCode:string,regionCode:string,roleCode:string,socket:Socket):Promise<Officer|null>{
		try{
			const conn=await getDBConnection();
			const result=await Officer.findByCode(conn,officerCode);
			if(result.code!=0){
				console.log(`[setOfficerJoined] result.code=${result.code}`);
				return null;
			}
			const officer=result.officer;
			if(officer==null){
				console.log(`[setOfficerJoined] officer=null`);
				return null;
			}
			const origOfficers=this.officers.values();
			for(const origOfficer of origOfficers){
				if(origOfficer==officer){
					continue;
				}
				officer.syncPeerLocation(origOfficer);
			}
			if(regionCode!=null){
				const region=await Region.findByCode(regionCode,conn);
				if(region!=null){
					officer.setRegion(region);
				}
			}
			if(roleCode!=null){
				const role=await Role.findByCode(roleCode,conn);
				if(role!=null){
					officer.setRole(role);
				}
			}
			officer.addSocket(socket);
			this.officers.set(officer.id,officer);
			return officer;
		}catch(e:any){
			console.error(e);
			console.log(`[setOfficerJoined] exception=${e.toString()}`);
			return null;
		}
	}
	async loop():Promise<void>{
		while(true){
			await this.syncOfficerLocations();
			this.broadcastOfficerMessages();
			await new Promise(function(resolve){
				setTimeout(resolve,50);
			});
		}
	}
	pushPendingMessage(pendingMessage:PendingMessage):PendingMessage{
		this.pendingMessages.push(pendingMessage);
		return pendingMessage;
	}
	setOfficerOffline(officer:Officer):void{
		this.officers.delete(officer.id);
	}
	setOfficerLocationUpdated(officer:Officer):void{
		this.updatedOfficers.set(officer.id,officer);
	}
}
