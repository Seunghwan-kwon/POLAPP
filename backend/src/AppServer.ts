import{Socket}from"socket.io";
import Police from"./Police.js";
import OfficerClient from"./OfficerClient.js";
import PendingMessage from"./PendingMessage.js";
import DBConnection from"./DBConnection.js";
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
	officerLocationUpdates:Map<number,number>;
	officersByRegion:Map<string,Map<number,OfficerClient>>;
	officerClients:Map<number,OfficerClient>;
	pendingMessages:Array<PendingMessage>;
	constructor(){
		this.officerLocationUpdates=new Map<number,number>();
		this.officersByRegion=new Map<string,Map<number,OfficerClient>>();
		this.officerClients=new Map<number,OfficerClient>();
		this.pendingMessages=new Array<PendingMessage>();
	}
	async syncOfficerLocations(){
		const updatedPoliceIds=this.officerLocationUpdates.keys();
		for(const policeId of updatedPoliceIds){
			const officerClient=this.officerClients.get(policeId);
			if(officerClient==null){
				console.log("[AppServer.syncOfficerLocations] officerClient=null");
				continue;
			}
			if(officerClient.officerId==null){
				console.log("[AppServer.syncOfficerLocations] officerClient.officerId=null");
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
			const policeIds=this.officerClients.keys();
			for(const _policeId of policeIds){
				if(_policeId===policeId){
					continue;
				}
				const peerOfficerClient=this.officerClients.get(_policeId);
				if(peerOfficerClient==null){
					console.log("[syncOfficerLocations] peerOfficerClient=null");
					continue;
				}
				peerOfficerClient.syncPeerLocation(officerClient.officerId,officerClient.x,officerClient.y);
			}
		}
		this.officerLocationUpdates.clear();
	}
	broadcastOfficerMessages(){
		for(const pendingMessage of this.pendingMessages){
			const region=pendingMessage.region;
			const peerOfficerClients=this.officersByRegion.get(region);
			if(peerOfficerClients==null){
				continue;
			}
			for(const peerOfficerClient of peerOfficerClients.values()){
				if(peerOfficerClient.policeId===pendingMessage.senderPoliceId){
					continue;
				}
				peerOfficerClient.syncPeerMessage(pendingMessage.senderOfficerId,pendingMessage.region,pendingMessage.text,pendingMessage.timestamp);
			}
		}
		this.pendingMessages.length=0;
	}
	async setOfficerJoined(officerId:string,region:string,socket:Socket):Promise<OfficerClient|null>{
		const conn=await getDBConnection();
		const getPoliceIdResult=await Police.getPoliceId(conn,officerId);
		if(getPoliceIdResult.code!=0){
			console.log("[setOfficerJoined] getPoliceIdResult.code="+getPoliceIdResult.code);
			return null;
		}
		const socketPoliceId=getPoliceIdResult.policeId;
		if(socketPoliceId==null){
			console.log("[setOfficerJoined] socketPoliceId=null");
			return null;
		}
		const origOfficerClients=this.officerClients.values();
		const officerClient=this.getOfficerClient(socketPoliceId);
		officerClient.officerId=officerId;
		officerClient.setRegion(region);
		officerClient.addSocket(socket);
		for(const origOfficerClient of origOfficerClients){
			if(origOfficerClient.officerId==null){
				continue;
			}
			if(origOfficerClient.policeId===officerClient.policeId){
				continue;
			}
			officerClient.syncPeerLocation(
				origOfficerClient.officerId,
				origOfficerClient.x,
				origOfficerClient.y
			);
		}
		return officerClient;
	}
	async loop(){
		while(true){
			await this.syncOfficerLocations();
			this.broadcastOfficerMessages();
			await new Promise(function(resolve){
				setTimeout(resolve,100);
			});
		}
	}
	getOfficerClient(policeId:number):OfficerClient{
		let officerClient=this.officerClients.get(policeId);
		if(officerClient==null){
			officerClient=new OfficerClient(policeId,this);
			this.officerClients.set(policeId,officerClient);
		}
		return officerClient;
	}
	pushPendingMessage(pendingMessage:PendingMessage):PendingMessage{
		this.pendingMessages.push(pendingMessage);
		return pendingMessage;
	}
	setOfficerOffline(policeId:number){
		this.officerClients.delete(policeId);
	}
	removeOfficerFromRegion(region:string,policeId:number){
		const officers=this.officersByRegion.get(region);
		if(officers==null){
			return;
		}
		officers.delete(policeId);
	}
	setOfficerLocationUpdated(policeId:number){
		this.officerLocationUpdates.set(policeId,1);
	}
	setOfficerRegion(region:string,officerClient:OfficerClient):number{
		const officers=this.officersByRegion.get(region);
		if(officers==null){
			return-1;
		}
		if(officerClient.region!=null){
			this.removeOfficerFromRegion(officerClient.region,officerClient.policeId);
		}
		officers.set(officerClient.policeId,officerClient);
		return 0;
	}
}
