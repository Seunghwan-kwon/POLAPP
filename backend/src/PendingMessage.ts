export default class PendingMessage{
	senderPoliceId:number;
	senderOfficerId:string;
	region:string;
	text:string;
	timestamp:string;
	constructor(senderPoliceId:number,officerId:string,region:string,text:string,timestamp:string){
		this.senderPoliceId=senderPoliceId;
		this.senderOfficerId=officerId;
		this.region=region;
		this.text=text;
		this.timestamp=timestamp;
	}
}
