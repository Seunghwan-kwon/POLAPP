import Officer from"./Officer.js";
import Region from"./Region.js";
export default class PendingMessage{
	sender:Officer;
	content:string;
	timestamp:string;
	constructor(sender:Officer,content:string,timestamp:string){
		this.sender=sender;
		this.content=content;
		this.timestamp=timestamp;
	}
}
