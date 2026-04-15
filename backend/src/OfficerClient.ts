import{Socket}from"socket.io";
import AppServer from"./AppServer.js";
import PendingMessage from"./PendingMessage.js";
export default class PoliceClient{
	appServer:AppServer;
	sockets:Map<string,Socket>;
	x:number;
	y:number;
	policeId:number;
	officerId:string|null;
	region:string|null;
	constructor(policeId:number,appServer:AppServer){
		this.x=0;
		this.y=0;
		this.policeId=policeId;
		this.officerId=null;
		this.region=null;
		this.sockets=new Map<string,Socket>();
		this.appServer=appServer;
	}
	addSocket(socket:Socket){
		this.sockets.set(socket.id,socket);
	}
	removeSocket(socketId:string){
		this.sockets.delete(socketId);
		const offline=this.sockets.size==0;
		if(offline){
			this.appServer.setOfficerOffline(this.policeId);
		}
	}
	setLocationUpdated(x:number,y:number):void{
		this.x=x;
		this.y=y;
		this.appServer.setOfficerLocationUpdated(this.policeId);
	}
	pushRadioMessage(message:string,timestamp:string):PendingMessage|null{
		if(this.officerId==null){
			return null;
		}
		if(this.region==null){
			return null;
		}
		const pendingMessage=new PendingMessage(this.policeId,this.officerId,this.region,message,timestamp);
		this.appServer.pushPendingMessage(pendingMessage);
		return pendingMessage;
	}
	setRegion(region:string){
		this.appServer.setOfficerRegion(region,this);
		this.region=region;
	}
	syncPeerLocation(officerId:string,x:number,y:number){
		for(const socket of this.sockets.values()){
			socket.emit("updateColleagueLocation",{
				officerId,
				latitude:x,
				longitude:y
			});
		}
	}
	syncPeerMessage(officerId:string,region:string,message:string,timestamp:string){
		for(const socket of this.sockets.values()){
			socket.emit("receiveRadioMessage",{
				officerId,
				region,
				message,
				timestamp
			});
		}
	}
}
