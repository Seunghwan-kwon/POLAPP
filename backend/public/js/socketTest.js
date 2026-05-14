"use strict";
const socket=io("/");
class Case{
	constructor(id){
		this.id=id;
		this.name=String(id);
	}
}
const caseMap=new Map();
function setCaseComplete(caseId){
	const caseObject=caseMap.get(caseId);
	if(caseObject==null){
		return;
	}
	caseObject.setComplete();
}
class UIUpdater{
	constructor(){
		this.nextFunctionId=1;
		this.functions=new Map();
	}
	addFunction(updater){
		const functionId=this.nextFunctionId++;
		this.functions.set(functionId,updater);
		return functionId;
	}
	run(params){
		const functions=this.functions.values();
		for(const f of functions){
			f(params);
		}
	}
}
const uiUpdaters=new Map();
function registerUIUpdater(key,updater){
	let uiUpdater=uiUpdaters.get(key);
	if(uiUpdater==null){
		uiUpdater=new UIUpdater();
		uiUpdaters.set(key,uiUpdater);
	}
	uiUpdater.addFunction(updater);
}
function updateUI(key,params){
	const uiUpdater=uiUpdaters.get(key);
	if(uiUpdater==null){
		return;
	}
	uiUpdater.run(params);
}
let joinButton=null;
registerUIUpdater("joined",function([joined]){
	if(joined){
		joinButton.hide();
	}else{
		joinButton.show();
	}
});
registerUIUpdater("caseComplete",function([caseId]){
	caseList.removeData(caseId);
});
registerUIUpdater("caseAssigned",function([caseId]){
	caseList.scroll(0);
});
registerUIUpdater("position",function([officerId]){
	const policeList=policeMap.values();
	ctx.clearRect(0,0,canvas.width,canvas.height);
	for(const police of policeList){
		ctx.beginPath();
		ctx.arc(police.x,police.y,4,0,Math.PI*2);
		ctx.fillStyle="black";
		ctx.fill();
		ctx.strokeText(police.officerId,police.x,police.y);
	}
});
socket.on("disconnect",(reason)=>{
	console.log(`Diconnected reason=${reason}`);
	setJoined(false);
});
socket.on("caseComplete",(caseId)=>{
	setCaseComplete(caseId);
	updateUI("caseComplete",[caseId]);
});
socket.on("caseAssigned",(caseId)=>{
	addCase(caseId);
	updateUI("caseAssigned",[caseId]);
});
const policeMap=new Map();
function addPolice(policeId){
	if(policeMap.has(policeId)){
		return;
	}
	const police=new Police(policeId);
	policeMap.set(policeId,police);
}
socket.on("policeAssigned",(policeId)=>{
	addPolice(policeId);
	updateUI("policeAssigned",[policeId]);
});
class Police{
	constructor(officerId){
		this.x=0;
		this.y=0;
		this.officerId=officerId;
	}
	setLocation(x,y){
		this.x=x;
		this.y=y;
	}
}
function updatePoliceLocation(officerId,x,y){
	let police=policeMap.get(officerId);
	if(police==null){
		police=new Police(officerId);
		policeMap.set(officerId,police);
	}
	police.setLocation(x,y);
}
let ctx;
let canvas;
socket.on("updateColleagueLocation",({officerId,latitude,longitude})=>{
	updatePoliceLocation(officerId,latitude,longitude);
	updateUI("position",[officerId]);
});
//let myOfficerId=null;
let joined=false;
function setJoined(b){
	joined=b;
	updateUI("joined",[joined]);
}
let positionX,positionY;
let lastPositionSendTime=0;
let sendPositionTimeout=null;
function main(){
	document.body.style.margin="0";
	const inputPanel=document.createElement("div");
	{
		const e=inputPanel;
		const codeBox=document.createElement("input");
		{
			const e=codeBox;
			e.value="P-0001";
			e.type="text";
		}
		e.appendChild(codeBox);
		const regionBox=document.createElement("input");
		{
			const e=regionBox;
			e.value="DEFAULT";
			e.type="text";
		}
		e.appendChild(regionBox);
		const roleBox=document.createElement("input");
		{
			const e=roleBox;
			e.value="NONE";
			e.type="text";
		}
		e.appendChild(roleBox);
		const submitBox=document.createElement("div");
		{
			const e=submitBox;
			e.style.border="1px solid #000";
			e.style.padding="2px";
			e.style.cursor="pointer";
			e.innerText="Join";
			joinButton={
				show:()=>{
					submitBox.style.display="block";
				},
				hide:()=>{
					submitBox.style.display="none";
				}
			};
			e.addEventListener("click",(e)=>{
				socket.emit("join",{
					officerId:codeBox.value,
					region:regionBox.value,
					role:roleBox.value
				});
				setJoined(true);
			});
		}
		e.appendChild(submitBox);
	}
	document.body.appendChild(inputPanel);
	canvas=document.createElement("canvas");
	{
		const e=canvas;
		e.width=400;
		e.height=400;
		e.style.border="1px solid #000";
		const MAX_DELAY=80;
		canvas.addEventListener("mousemove",(e)=>{
			if(!joined){
				return;
			}
			positionX=e.clientX;
			positionY=e.clientY;
			if(sendPositionTimeout==null){
				const t=new Date().getTime();
				const dt=t-lastPositionSendTime;
				if(dt>MAX_DELAY-1){
					socket.emit("sendMyLocation",{
						//officerId:myOfficerId,
						latitude:positionX,
						longitude:positionY
					});
					lastPositionSendTime=t;
				}else{
					sendPositionTimeout=setTimeout(function(){
						socket.emit("sendMyLocation",{
							//officerId:myOfficerId,
							latitude:positionX,
							longitude:positionY
						});
						sendPositionTimeout=null;
					},MAX_DELAY-dt);
				}
			}
		});
		ctx=e.getContext("2d");
	}
	document.body.appendChild(canvas);
}
main();
