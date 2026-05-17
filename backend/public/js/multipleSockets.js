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
		region:regionCode,
		role:roleCode
	});
	return instance;
}
const instance0=createSocket("P-1000","SEOUL_NOWON","NONE");
const instance1=createSocket("P-1001","SEOUL_NOWON","NONE");
const instance2=createSocket("ADMIN-001","DEFAULT","ADMIN");
setTimeout(()=>{
	instance0.close();
	setTimeout(()=>{
		instance1.close();
	},500);
},500);
