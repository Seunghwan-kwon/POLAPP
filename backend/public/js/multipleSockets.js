"use strict";
window.addEventListener("error",(e)=>{
	alert(e);
});
function createSocket(officerCode,regionCode,roleCode){
	const instance={};
	instance.close=()=>{
		socket.disconnect();
	};
	const socket=io("/");
	socket.on("removeColleagueLocation",({officerId})=>{
		alert(`[${officerCode}] removeColleagueLocation officerId=${officerId}`);
	});
	socket.on("receiveColleagueLocation",({officerId,region,longitude,latitude})=>{
		alert(`[${officerCode}] receiveColleagueLocation officerId=${officerId},region=${region},longitude=${longitude},latitude=${latitude}`);
	});
	socket.emit("join",{
		officerId:officerCode,
		role:roleCode
	});
	return instance;
}
let instance;
//const instance1=createSocket("P-1001","SEOUL_NOWON","NONE");
//const instance2=createSocket("ADMIN-001","DEFAULT","ADMIN");
/*
setTimeout(()=>{
	instance.close();
	setTimeout(()=>{
		instance1.close();
	},500);
},500);
*/
(async()=>{
for(let i=0;i<4;++i){
	instance=createSocket("P-1000","NONE");
	await new Promise((resolve)=>setTimeout(resolve,100));
	instance.close();
}
})();
