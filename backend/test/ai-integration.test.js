const assert=require("node:assert/strict");
const test=require("node:test");
const{normalizeDetections,normalizeThreatInput}=require("../dist/AiIntegration.js");

test("위협 알림 입력을 정규화한다",()=>{
	const input=normalizeThreatInput({
		eventId:"event-1",
		sessionId:"session-1",
		category:"weapon",
		alertLabel:"흉기",
		riskLevel:4,
		evidenceIndex:140,
		reasons:["칼 감지"],
		occurredAt:"2026-10-04T12:00:00+09:00"
	});
	assert.ok(input);
	assert.equal(input.evidenceIndex,100);
	assert.deepEqual(input.reasons,["칼 감지"]);
});

test("잘못된 위험 단계는 거부한다",()=>{
	assert.equal(normalizeThreatInput({
		eventId:"event-2",
		riskLevel:5,
		evidenceIndex:20,
		occurredAt:"2026-10-04T12:00:00Z"
	}),null);
});

test("카메라 탐지값은 지원 클래스만 남긴다",()=>{
	const detections=normalizeDetections([
		{label:"knife",score:1.4,box:[-1,0.2,0.8,2]},
		{label:"person",score:0.9,box:[0,0,1,1]}
	]);
	assert.equal(detections.length,1);
	assert.equal(detections[0].displayLabel,"칼");
	assert.equal(detections[0].score,1);
	assert.deepEqual(detections[0].box,[0,0.2,0.8,1]);
});
