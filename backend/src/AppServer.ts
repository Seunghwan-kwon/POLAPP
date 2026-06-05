import{Socket}from"socket.io";
import Officer from"./Officer.js";
import PendingMessage from"./PendingMessage.js";
import DBConnection from"./DBConnection.js";
import Region from"./Region.js";
import Role from"./Role.js";
import{getMySqlConnection}from"./MySqlConnection.js";
import{getDateStr}from"./Utils.js";
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
	lastLocationUpdated:number;
	locationUpdateTimeout:ReturnType<typeof setTimeout>|null;
	updatedOfficers:Map<number,Officer>;
	officers:Map<number,Officer>;
	adminRole:Role|null;
	constructor(){
		this.lastLocationUpdated=0;
		this.locationUpdateTimeout=null;
		this.updatedOfficers=new Map<number,Officer>();
		this.officers=new Map<number,Officer>();
		this.adminRole=null;
	}
	async getAdminRole():Promise<Role|null>{
		if(this.adminRole==null){
			let conn;
			try{
				conn=await getDBConnection();
				const role=await Role.findByCode("ADMIN",conn);
				this.adminRole=role;
			}catch(ex){
				console.error(ex);
				return null;
			}finally{
				conn?.release();
			}
		}
		return this.adminRole;
	}
	async broadcastOfficerOffline(officer:Officer){
		const region=officer.region;
		if(region!=null){
			let peers=region.officers.values();
			for(const peer of peers){
				if(peer==officer){
					continue;
				}
				peer.notifyPeerOffline(officer);
			}
		}
		const adminRole=await this.getAdminRole();
		if(adminRole!=null){
			const peers=adminRole.officers.values();
			for(const peer of peers){
				if(peer==officer){
					continue;
				}
				peer.notifyPeerOffline(officer);
			}
		}
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
			if(officer.initialLocationUpdate){
				officer.initialLocationUpdate=false;
			}
		}
		this.updatedOfficers.clear();
	}
	async setOfficerJoined(officerCode:string,socket:Socket):Promise<Officer|null>{
		let conn;
		try{
			conn=await getDBConnection();
			const officer=await Officer.findByCode(conn,officerCode,this);
			if(officer==null){
				console.log(`[${getDateStr()}] [setOfficerJoined] findByCode returned null officerCode=${officerCode}`);
				return null;
			}
			officer.setSocket(socket);
			officer.setRegion();
			const origOfficers=this.officers.values();
			for(const origOfficer of origOfficers){
				if(origOfficer==officer){
					continue;
				}
				officer.syncPeerLocation(origOfficer);
			}
			officer.setRole();
			this.officers.set(officer.id,officer);
			return officer;
		}catch(e:any){
			console.error(e);
			console.log(`[${getDateStr()}] [setOfficerJoined] exception=${e.toString()}`);
			return null;
		}finally{
			conn?.release();
		}
	}
	async setOfficerOffline(officer:Officer):Promise<void>{
		console.log(`[${getDateStr()}] [setOfficerOffline] officer.code=${officer.code}`);
		this.officers.delete(officer.id);
		await this.broadcastOfficerOffline(officer);
	}
	setOfficerLocationUpdated(officer:Officer):void{
		this.updatedOfficers.set(officer.id,officer);
		const t=Date.now();
		if(t-this.lastLocationUpdated>40){
			if(this.locationUpdateTimeout==null){
				this.syncOfficerLocations().then(()=>{
					this.lastLocationUpdated=Date.now();
				});
			}
		}else{
			if(this.locationUpdateTimeout==null){
				this.locationUpdateTimeout=setTimeout(()=>{
					this.locationUpdateTimeout=null;
					this.syncOfficerLocations().then(()=>{
						this.lastLocationUpdated=Date.now();
					});
				},25);
			}
		}
	}
	async pushPendingMessage(sender:Officer,regionCode:string,message:string,timestamp:string):Promise<number>{
	      	if(regionCode==="ALL"){
			const pendingMessage=new PendingMessage(sender,null,message,timestamp);
			const peers=this.officers.values();
			for(const peer of peers){
				if(sender==peer){
					continue;
				}
				peer.syncPeerMessage(pendingMessage);
			}
			return 0;
		}else{
			let conn;
			try{
				conn=await getDBConnection();
	      			const region=await Region.findByCode(regionCode,conn);
				if(region==null){
					console.log(`[pushPendingMessage] No such region code=${regionCode}`);
					return -1; 
				}
				const pendingMessage=new PendingMessage(sender,region,message,timestamp);
				const peers=region.officers.values();
				for(const peer of peers){
					if(sender==peer){
						continue;
					}
					peer.syncPeerMessage(pendingMessage);
				}
				return 0;
			}catch(e){
				console.error(e);
				return-1;
			}finally{
				conn?.release();
			}
		}
	}
	broadcast(name:string,arg:any):void{
		for(const officer of this.officers.values()){
			officer.emit(name,arg);
		}
	}
}
