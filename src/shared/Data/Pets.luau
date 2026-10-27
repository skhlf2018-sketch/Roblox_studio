--!strict
-- 6판: Plants 로 이름 바뀜 (펫 134종 → 식물 134종), 정리 예정. 옛 코드·테스트가 require(Data.Pets) 하는 호환 파일 —
-- 새 코드는 require(Data.Plants) 를 쓰세요. (Pet 타입 = Plants.Plant)
local Plants = require(script.Parent.Plants)
export type Pet = Plants.Plant
export type PetSource = Plants.PlantSource
return Plants
