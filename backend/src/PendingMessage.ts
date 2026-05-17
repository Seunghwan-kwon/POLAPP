import Officer from"./Officer.js";
import Region from"./Region.js";
export default class PendingMessage{
	sender:Officer;
	region:Region|null;
	content:string;
	timestamp:string;
	constructor(sender:Officer,region:Region|null,content:string,timestamp:string){
		this.sender=sender;
		this.region=region;
		this.content=content;
		this.timestamp=timestamp;
	}
}
