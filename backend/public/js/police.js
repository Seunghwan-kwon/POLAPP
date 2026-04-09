"use strict";
const socket=io();
class Case{
	constructor(id){
		this.id=id;
		this.name=String(id);
	}
}
async function getAssignedCases(startId,size){
	const cases=[];
	let id=startId;
	for(let i=0;i<size;++i){
		const caseObject=new Case(id);
		cases.push(caseObject);
		id++;
	}
	return[0,cases];
}
function createRootElement(){
}
function createNotification(text){
	alert(text);
}
function createCaseList(){
	let contentElement;
	const caseListElement=document.createElement("div");
	{
		const e=caseListElement;
		e.style.userSelect="none";
		const containerElement=document.createElement("div");
		{
			const e=containerElement;
			let state=0;
			let mouseY;
			e.addEventListener("pointerdown",function(e){
				if(state==0){
					state=1;
					mouseY=e.clientY;
				}
			});
			document.addEventListener("pointermove",function(e){
				if(state==1){
					const dY=mouseY-e.clientY;
					mouseY=e.clientY;
					object.scroll(-dY);
				}
			});
			document.addEventListener("pointerup",function(e){
				if(state==1){
					state=0;
				}
			});
			e.style.display="flex";
			e.style.width="300px";
			e.style.height="400px";
			e.style.position="relative";
			e.style.overflowY="hidden";
			contentElement=document.createElement("div");
			{
				const e=contentElement;
				e.style.display="flex";
				e.style.position="absolute";
				e.style.width="100%";
			}
			e.appendChild(contentElement);
		}
		e.appendChild(containerElement);
	}
	const object={
		items:new Map(),
		itemsByDataId:new Map(),
		offset:0,
		size:400,
		itemSize:100
	};
	object.getElement=function(){
		return caseListElement;
	};
	object.removeHidden=function(){
		const prevIndexes=object.items.keys();
		for(const prevIndex of prevIndexes){
			if(prevIndex<object.startIndex||prevIndex>object.endIndex){
				object.removeItem(prevIndex);
			}
		}
	};
	object.scroll=function(d){
		let nextOffset=object.offset+d;
		if(nextOffset<0){
			nextOffset=0;
			d=nextOffset-object.offset;
			if(Math.abs(d)<0.0001){
				return;
			}
		}
		object.offset=nextOffset;
		contentElement.style.top=-object.offset+"px";
		const itemCount=Math.floor(object.size/object.itemSize);
		object.startIndex=Math.floor(object.offset/object.itemSize);
		object.endIndex=object.startIndex+itemCount-1;
		let fetchStartId=1;
		let fetchStartIndex=object.startIndex;
		for(let idx=object.startIndex;idx<=object.endIndex;++idx){
			const item=object.items.get(idx);
			if(item!=null){
				fetchStartId=item.data.id;
				fetchStartIndex=idx;
			}else{
				object.update(fetchStartIndex,fetchStartId);
				break;
			}
		}
	};
	object.removeItem=function(itemIdx){
		const item=object.items.get(itemIdx);
		if(item==null){
			return;
		}
		object.itemsByDataId.delete(item.data.id);
		object.items.delete(itemIdx);
		item.element.remove();
		console.log("Removed idx="+itemIdx);
	};
	object.removeData=function(dataId){
		const item=object.itemsByDataId.get(dataId);
		if(item==null){
			return;
		}
		object.itemsByDataId.delete(dataId);
		object.items.delete(item.idx);
		item.element.remove();
	};
	object.clear=function(){
		object.items.clear();
		object.itemsByDataId.clear();
	};
	object.addItem=function(idx,data){
		let item;
		item=object.items.get(idx,item);
		if(item!=null){
			item.element.remove();
			object.itemsByDataId.delete(item.data.id);
		}
		item={
			idx,
			data,
		};
		const itemElement=document.createElement("div");
		{
			const e=itemElement;
			e.style.position="absolute";
			e.style.top=(idx*object.itemSize)+"px";
			e.innerText=data.name;
		}
		item.element=itemElement;
		object.items.set(idx,item);
		object.itemsByDataId.set(data.id,item);
		contentElement.appendChild(itemElement);
	};
	let currentViewId=0;
	const fetchSize=8;
	object.update=function(fetchStartIndex,fetchStartId){
		const viewId=++currentViewId;
		console.log("Update fetchStartIndex="+fetchStartIndex);
		getAssignedCases(fetchStartId,fetchSize).then(function([code,cases]){
			if(code!=0){
				return;
			}
			if(viewId!=currentViewId){
				return;
			}
			let idx=fetchStartIndex;
			object.removeHidden();
			for(const caseObject of cases){
				object.addItem(idx++,caseObject);
			}
		});
	};
	object.scroll(0);
	return object;
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
registerUIUpdater("caseComplete",function([caseId]){
	caseList.removeData(caseId);
});
registerUIUpdater("caseAssigned",function([caseId]){
	caseList.scroll(0);
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
function updatePoliceLocation(policeId,x,y){
	const police=policeMap.get(policeId);
	if(police==null){
		return;
	}
	police.setLocation(x,y);
}
socket.on("position",(policeId,x,y)=>{
	updatePoliceLocation(policeId,x,y);
	updateUI("position",[policeId]);
});
let caseList=null;
function main(){
	document.body.style.margin="0";
	caseList=createCaseList();
	const caseListElement=caseList.getElement();
	document.body.appendChild(caseListElement);
}
main();
