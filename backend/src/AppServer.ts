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
		}
		this.updatedOfficers.clear();
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
	async setOfficerOffline(officer:Officer):Promise<void>{
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
			try{
				const conn=await getDBConnection();
	      			const region=await Region.findByCode(regionCode,conn);
				if(region==null){
					console.log(`[pushPendingMessage] No such regione code=${regionCode}`);
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
			}
		}
	}
}
