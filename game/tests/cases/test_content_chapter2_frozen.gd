extends RefCounted

## Chapter 2 content is FROZEN.
##
## Chapter 3 ("A Day With Little Buddy") is authored by appending to the same
## five task files, the same `objects.json` and the same `vocabulary.json` that
## Chapter 2 already ships from. Appending is safe; *editing* is not -- a shipped
## device profile stores completed task ids, the save migration seeds levels from
## them, and `feed_milk.json` is a live contract with the build on the physical
## iPhone. A one-word "improvement" to `feedMilk`'s prompt would be invisible in
## every other test and would quietly change what a child who already owns this
## game hears.
##
## So every record that existed before the slice is pinned by the SHA-256 of its
## canonical JSON (`JSON.stringify(record, "", true)` sorts keys, so key order in
## the file is not what is being asserted -- the content is).
##
## `morningRoutine` is deliberately NOT in the mission table: it is the Chapter 3
## level `gettingDressed`, and the slice retunes it. It is asserted separately,
## below, to still be a Chapter 3 level.
##
## When a record legitimately changes, the fix is to re-derive the hash and say
## why in the commit message -- never to delete the row.

const ContentLibraryScript := preload("res://scripts/content/content_library.gd")

## Every task that existed before the Chapter 3 slice (43 of them).
const FROZEN_TASKS: Dictionary = {
	"bedtimeBlanket": "4b29fcc2fc227043fdcacc8c858cb27528ec3bbd5f5446ee2a1c88ec262e7bfb",
	"bedtimePajamas": "f3a596e34be512c863b9039cf216944f4577b6af004460d7045035a7aa61ff1d",
	"bedtimePillow": "359c8dd63fbb4f4f9e7a38c18727ce6756e4ad9d9898491b677786cc88a58bb2",
	"bedtimeTeddy": "b39b5656e4690b16b1c16066359ddef6d5009dc8f0d454513342e7fb4ae04593",
	"blockInToyBox": "2b5ce8e291ba15d086d9647950fb97f30a1d103e57f5e61b374b37993cff18bd",
	"brushTeeth": "6c847e2f9f9d85a236d3c6c41cd2eda0ef16b71e419c25bf050d8b86a20e4dd0",
	"dryWithTowel": "2448b2d2a84f4f24a58bd779e5b768dd86efda0b1472bdd83656a67ecbd7c46d",
	"feedApple": "38a3bd9efce92118781a6161ce0f44b28b523e47e83ffb583e880285fb184de5",
	"feedBanana": "74f6bd40bf7bf224666059a68bba1044b434a86d244ec3802b531ba0e4fa253e",
	"feedMilk": "633777d0eeb0eed3df9baefee1bb43c3adb8a2cfbcfca3977267e5b4cbb9e9e0",
	"feedWater": "defdc3355fc19acdf63ce3cf04262db384c5cb389f30f418127d50a9b3fb32d0",
	"findBall": "155523d4a9b6b2d6ae36a366d627996297b68f49746dd282d9982b4161ae246f",
	"findBlanket": "f70277d5c4a70385309c71ba8017f03fb67e93953d8ed72dae6eb06e01d1762f",
	"findBowl": "cccf3871657ceb9398ac915c6ea1141d6f79aeeb2b0cff9dfb5c8f98a6e8deea",
	"findCircle": "30603b78f478df01db7e6cd96a48a26b1c0cd6a10d58c2bf9699aab2c125e376",
	"findShoes": "2f7c3ecfa46b1f490f120cbaaf55552ead6e072fe8b2fc3ff15de724c9e8f3c9",
	"findSpoon": "ea441a1a872cee5df3fd70df3e39483aab32ce87a5d4978a3372c2a8e2ae7b37",
	"findSquare": "1c75321e8b7459de87c59c12375019c388dbb472d7eeb4943de2ed8782005c21",
	"findStar": "6a034970d639d227a0f4ad74bb1c766a871e32b611852ce9bc913790cb984e29",
	"findTowel": "7da86bee45c343ff1f19bd86eb6fa16596a6de677d67a93174adf05ad5c2892c",
	"giveBall": "ad0c94386b9f8c0c3ea25b637e1f774f9da2b251568bed5bc440f6c8bf4deba8",
	"giveBathToy": "ed50be37886c272e5786cdc6f251dfc2cb8c97557e370ef834b160d15d09163d",
	"giveCup": "6d60e7d152d3ea5b404e2496b3faa9993da4ab22b7d6f888653f820bcf3db03d",
	"giveSoap": "3d669e8f7a0e0d7d6c6223486e91233e33480f6d9d5d97184ce2580d278f99f7",
	"giveTeddy": "f61a6f4a634bdb0551811ecc6f8ed64da42a048f1982a523b3634c2317270922",
	"sayBall": "cc90d5160f1b3a767fba1009a57b6b3c32a49f7e8b45c084cd44fe9994c017a1",
	"sayBanana": "1a3f33e49ee29483bb915c79e89865b33bce878ad1fdfd52f38c3f5acc9b7bf5",
	"sayBlue": "c0eaad7b3b2bdd449645755c7d82cc029872126d1cb75689fc34ee5ac3f8577f",
	"sayCircle": "5b918eb361fe1adf035c7aba4f5c9a13c8ef64ffd18e7820f99f73fbbab702ed",
	"sayGoodNight": "c7fc8d39e36df1dfb9d7e99ea8add04f98d34d6115074dbea0d781926ee41cab",
	"sayMilk": "4a4fb8d916fb5c76c3af766fa0837c58839508585cf693c81d43fea93e7d8cef",
	"sayPillow": "b7712e4afddc8b52159b582da4e4970aac274ee2c8ed5ac54522b91f47870be3",
	"sayToothbrush": "ea3162686d4c8f079e36bcbee509af5d2c6af49e4a652937ffac37c6e22083c7",
	"sayTowel": "3350887ca50d392bcb53fb933fc3a41537ff7fe34f407e895c174a64b7dd06af",
	"tidyToyBox": "f07fa81fed8bd785c31905c76da5b9bc67343f6865368b48685566cf361cb96b",
	"turnOffLamp": "a27ff08e66ab631b58639db58b60a331d0e5c6dc797282d4cf4f467a367d6e94",
	"wearBlueShirt": "1ab21ccdc21d95dcead236e2f3ae3da21eb21204bbf9d6d3d3fc0200d8d6268f",
	"wearHat": "c03668faeb4d920595b6152e8714053e80adba88d0bbba7e18199402d255df3d",
	"wearPajamas": "fb3621ef1fa7f23a501346312a48a0f4ddacbfc57b8bbaac03961a9568038690",
	"wearPants": "3f4a46e3b3ef0c7cafa286377fc132ac1646cdcfe55288e44e60f1cc3998a480",
	"wearRedShirt": "cd97004e5b525b02db215fb6333042a6d3c7f050ccc0c8b83351569d2524814f",
	"wearShoes": "6ae5be43437130705624b1c9a3b53bb178a4740c1a6c15fc02f88d911510b261",
	"wearYellowShirt": "9bf4942ad9054f2f6f297f9d16462ab0a82f856eacc13de85ab2ea510005035f",
}

## The five Chapter 2 missions plus the `sayItChallenge` bonus. `morningRoutine`
## is excluded on purpose: it is Chapter 3's `gettingDressed`.
const FROZEN_MISSIONS: Dictionary = {
	"bathTime": "c0f1ee5456a83e816ce456886b76e0b34b7d210ce51a6ea7692b2a116c6ba276",
	"bedtimeRoutine": "3b85b9034c55fa45d9764e8895ea5b0d5fbb51033dddf0c64dc1d94728ec867e",
	"colorsAndShapes": "c07235d3699e203041bb1333b94a96a7e10cb05dc8e9c8177b470451641b6083",
	"feedingTime": "4808fa5dbbe789b8c9936d5620910f7343a7bcaf6cbbc3e50c8214f418d5e2d0",
	"playTime": "31a6586c27714c9e07758d3e8191e62f2c86247c1a95f3cacc517bf0f6178d8d",
	"sayItChallenge": "9869ef3b4875ba272b532c37f8a42f7969b1f69ddda9dbbba4f3da240ef419c4",
}

## All 28 shipped objects. The slice adds no object and edits none; if it ever
## needs one, that is an `object_spawner.gd` change and a deliberate decision,
## not something that should be able to happen by accident in a JSON file.
const FROZEN_OBJECTS: Dictionary = {
	"apple": "b4d9e215c885a4f4c29b27293db3fcf7dfb31eac095f55f8445011cec6ec7205",
	"ball": "b315dc51698ecc3eeb8cdf23666c98b5400f1b0807ec80b84e07c56894c875c8",
	"banana": "50b6c4e393a0769d00ad92d8fe9fb45770710953d91fa5f89b4b8b8ffbe84251",
	"bathToy": "b40c5c2b95921181c0ca1ec08a8a35a54bac42caa196557b2dde66904af37aa2",
	"blanket": "6effe5a0d11339b4ebdceb5f641f9b8daeca0d43c88d5e08b76ec0eea3345dd8",
	"blocks": "2d81cfe77239f7df9684896d4b3dfafca58218701bbd1506db5a4861e52b813c",
	"blueShirt": "508b1be9c3d8d2175cc4add62a14dc8d0730b01fc902e2971f3cf740f166bed8",
	"bowl": "b26cbf30601401203d20d5443f4db9bf58c67cbe75ab372532f6db92d9de51bd",
	"circleToy": "29593da8b04163c12ac7cd94afe01e98a56f9a77251eb03d2c903f9aad94bdc0",
	"cup": "ae4d044e41ffd507d0c94d727a73c8ea7d4495e4d5d92910ffb7a2309abd643e",
	"hat": "cb4c74f401b7070f8b355a40e81466fb39eab18ab9c4b6fe0081f3c41562e888",
	"lamp": "3d770dc6517564c9ea54d0b737f97482aa6621e179c8a5161c40c525934eeb24",
	"milk": "aa154fa57d309441621e72b7e5ca812b671a3680237a80bb23656ec650f5448d",
	"pajamas": "5663e9a09b3f253812dd39aed57312bd727adf859d3de4c5a814bb90cb78c737",
	"pants": "12a030940c2cb0c7c3d4d8bc0cd95f734fead3ca082a5e4e528696d4e75a1dea",
	"pillow": "6fc5092129ec12dec68085d25f12d47099cf83a4b4a97f6c371fd099ed0747d3",
	"redShirt": "bbd88f333a7fba7c6534543ca7f2f5b0749d03365365135c06c012fff4febc52",
	"shoes": "c1eecab25da14c2a62867f263b0eea4bf388042fd03c1bf0a393ec3819c1bdb6",
	"soap": "b75b2003af7921f6e040e16adb13b97c6d81904f02c4068ef45ca3ebccfba3bd",
	"spoon": "a25ac527edadeeb88d33b7693d76af344c0aacbdee95caf1135b05127225e27c",
	"squareToy": "4a62d83b58cdebe670f510bb878051ee1f373ad33fa3f7d0a53a611630c1819d",
	"starToy": "0a5360f442d2d39b593cd4355305bcc04ca2e0f6b75f81a16e666baa4ef06260",
	"teddy": "013361e6af24a0453d4c13995365ae5c27076fa84356f26961c9acecd7687f0f",
	"toothbrush": "0c245961bddb9d5fc41bebb09edf18d3ab8a43f282d1023ecf4a4d782c818fe7",
	"towel": "09a471f0b42116a9f235b43034b81ec1f045512decd7f1af5373f956e6753903",
	"toyBox": "ad93e67323f141df72ce969fb6fdd7e708de36f5939274b98f4d17697020e666",
	"water": "8c1b3f1b0b3e2fbd44a00a839d4c2dd29432e73d17e169f7a38eda2e9ac6d194",
	"yellowShirt": "c9fcec19725fc94cd8d0b5872f86fbe55fdb3e848c4143947efb78a5fb840b24",
}

## The 46 words that shipped before the slice. The slice adds toddler words with
## the additive `stage`/`exposure` keys; it must not re-tier an existing record
## in place, because the Chapter 2 levels still teach them at the baby ceiling.
const FROZEN_WORDS: Dictionary = {
	"apple": "14e51866c5f13727c22ee431302a75ddbde8583ed501acdc99899035cf8931aa",
	"ball": "e62ccf395762c4ab810b2ed48e90221eec846befdaea8185e723db9c75c86bb0",
	"banana": "3efc394dcd9e4d005556990c5ad76676a36c8d23118c9a67956fc64db61ae4b1",
	"bath": "f77af1c450e53a7eb43bc032fa4359cc0337b62bb06b30e05c86bc6d634de363",
	"bed": "43c368d58eb3b5dd6a2b850720de709eb65859b2259e78daebb4359f253ad664",
	"blanket": "fbdd7f61f1df9e4658ffa7d5794efe151dbb97a1d9dd3c0d30612b6e47ea31db",
	"block": "2601af5e37faf758ce70c05d9b0f9b38128f3680d64ebaae86ee1ccc997fbb7b",
	"blue": "83194ff7efd9fe85275e23cf9de6da094a014f545d0790fd387eeda05a0f4853",
	"bowl": "53234bb272399caf996d0f2d53dbfc6dcfe8da818359fefd3314670bbf1584ca",
	"circle": "737dc9052b5ea5c133d7abd7052ea307acfe0cfd3a5474c6115b97504c6af8bc",
	"clean": "7612c492c6c909486bed0a5b52d04d6841e02fa1021cb447a79013d4b18fd942",
	"cup": "14552d6762ea4b505675f372ed6f64379c2dd800f826dbc68eb6404533f4f756",
	"drink": "5e94490563618d90d1019835009c63c7f3dbfa95ce7416c73693d38401ea9af8",
	"dry": "865d17cc0adef73061742c16cfdea703b4c1e799b75185fd9f5292fe81f5c459",
	"eat": "f3230451c689fb9bfb8e37172105130015fbcc8a35e732e87c0b7df0faaa9760",
	"goodNight": "838847c73d2f1c5afe442bfb7b55512b9c44844ca66a6d3bf679b1e357dd3f3f",
	"hat": "1d54e04f3d12b20f8be55efda3f1069ed8c48aa1a20051e566641c7411681755",
	"hungry": "7378f04652d362c5dc0943688d70eea0144729a44d9e0d09afbc36528ac3380b",
	"lamp": "b8bdce5bbb8d2ed555352a4a829e0b69b7ab218bc76596504e732e650dab2543",
	"milk": "aa225288767b477c7ef52ee008434addeae7ea64653be1a54e4ec2c35a0d6b4f",
	"moon": "13c0e129684c4d1841f542196a9f62cb26a4c4fa47b8103ee0867871a053b415",
	"night": "6889aca7fc622c86c690db9cd632305bb287f66ba55126973f8c8f448dbc7ad1",
	"pajamas": "7f493d8ffb5d7fc4f51f9474d2e4f5b654f9de8473ff8b5f629c867a925a2194",
	"pants": "94396a1ff164502131849077365304be51a000c1113e1ba5d1261ca396402da5",
	"pillow": "08b6727399b32baa52719b916a58aa59ac7548eaac0b998a9fa3e4e5a37ecb52",
	"play": "6954768986dd4213171758c9556550c64f16f8ee2750b6a3b554a4f7a5cd8556",
	"red": "a2213bee2350aad817b4c96015d050ddf6303158d34c9a479f0bce6c5da06112",
	"shirt": "e5d851257e54be2c2a7260d3a748c6268a07adcabb66b149e7dd601ddd299c0d",
	"shoes": "2dd27a55f5f4b3dff214abb53107a5452a2d4f2b2be1287c09aeafc327c4a5a6",
	"sleepy": "fe3f9eee81b62cbcd9da0fa66e74115f2ba66ee8be9cbcd76013390e55efe378",
	"soap": "3f8e8102f47fbfa47311ead7e7715f56c40a2ba891083da5602aaf56015814a0",
	"spoon": "a2453a9c45e64737352e2124b0f45681e69539bad2769a2290346e93e9159dd8",
	"square": "b7c7dae8939f0bd6599d07b76cb3b6f8ef11019dd2036438e71725ee6d4b08d3",
	"star": "1a6fe13b6e68f186b50251957613da88f80987608de157f9f890cede247ae88a",
	"teddy": "9274faa5ed341633925c116efa404cf83a52aba354ae544a8c04d3617b2b3133",
	"teeth": "305d87a1b39f044149a96835a8eb4b3af7979f3cbae6f4a63f791db2bc66bbaf",
	"thirsty": "12ccb34e1d2f8dc852113164f1734e057b464a1ea9bd56fd13559327f59dfb5c",
	"throw": "2f8a4760b0785af2e3a52f88d018874b2baba2fc9d7809aab6d5d2944209f182",
	"toothbrush": "67b712d5a4aae0d125ac1a50b90f4be3a75db1b54d6a95d80f64cbbc38fe3cc2",
	"towel": "df7835e765568df15da78cf0151764edcb2fc73e1a45268a7d7ccf5016f46a91",
	"toyBox": "63e86fb486821759352a7d20be054940bb5e8ffdc89676e4290b14580f7d3b17",
	"wash": "d1c9a76b2a1c0c116174785e353fe42372218d691582ab36a7a6561f6f35ca60",
	"water": "2d318393f770bbdada14f1b9eb379bf05f91b88212d7c27d2e18e1e22f70b8b7",
	"wear": "dcd59af95664a1e91190fd4b6e9bbcece7bafb0692aadb989cbda4354e6f2321",
	"wet": "e7fd792924e80a1f9240ed50ef7e00d57a9a3fe08408799c4618cd8d9b8a3f98",
	"yellow": "f0ef999853258e5f0bda15ad0fa5fbe60e0f4fde6b01107a03baea16a4dfdef0",
}

## The six phrases the live iPhone build maps onto `feedMilk`. Also asserted by
## `ContentValidator.validate_legacy_activity()`; repeated here because this is
## the file a reader opens to ask "what may I not change?".
const LEGACY_FEED_MILK_COMMANDS: Array[String] = [
	"milk",
	"give milk",
	"give baby milk",
	"give the baby milk",
	"give the baby some milk",
	"baby wants milk",
]


func test_name() -> String:
	return "content_chapter2_frozen"


func run():
	var failures: Array = []

	var library: Object = ContentLibraryScript.new()
	if library == null:
		return ["content_library.gd could not be instantiated"]
	library.load_all()

	failures.append_array(_check_frozen(library, "get_task", FROZEN_TASKS, "task"))
	failures.append_array(_check_frozen(library, "get_mission", FROZEN_MISSIONS, "mission"))
	failures.append_array(_check_frozen(library, "get_object", FROZEN_OBJECTS, "object"))
	failures.append_array(_check_frozen(library, "get_word", FROZEN_WORDS, "word"))
	failures.append_array(_test_legacy_feed_milk())
	failures.append_array(_test_getting_dressed_is_still_a_chapter_3_level(library))

	return failures


func _check_frozen(library: Object, getter: String, frozen: Dictionary, label: String) -> Array:
	var failures: Array = []
	for record_id: String in frozen.keys():
		var record: Variant = library.call(getter, record_id)
		if typeof(record) != TYPE_DICTIONARY or (record as Dictionary).is_empty():
			failures.append("%s '%s' has been DELETED; Chapter 2 content is frozen" % [label, record_id])
			continue
		var digest: String = JSON.stringify(record, "", true).sha256_text()
		if digest != String(frozen[record_id]):
			failures.append(
				"%s '%s' was EDITED (hash %s, expected %s). Chapter 3 may only APPEND records."
				% [label, record_id, digest.substr(0, 12), String(frozen[record_id]).substr(0, 12)]
			)
	return failures


## `feed_milk.json` is read by `ActivityLoader` on the physical device. Its six
## accepted phrases are the oldest contract in the project.
func _test_legacy_feed_milk():
	var failures: Array = []
	var path: String = "res://content/feeding/feed_milk.json"
	if not FileAccess.file_exists(path):
		return ["%s is missing" % path]
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return ["%s is not a JSON object" % path]
	var data: Dictionary = parsed

	if String(data.get("activityId", "")) != "feedMilk":
		failures.append("feed_milk.json: activityId must stay 'feedMilk'")

	var accepted: Variant = data.get("acceptedCommands", null)
	if typeof(accepted) != TYPE_ARRAY:
		failures.append("feed_milk.json: acceptedCommands must be an array")
		return failures
	for phrase: String in LEGACY_FEED_MILK_COMMANDS:
		if not (accepted as Array).has(phrase):
			failures.append("feed_milk.json: lost the accepted phrase '%s'" % phrase)
	return failures


## The slice retunes `morningRoutine`, so it is not hash-frozen. What must stay
## true is the thing other code keys on: it is still the Chapter 3 level
## `gettingDressed`, and it still runs under the same mission id.
func _test_getting_dressed_is_still_a_chapter_3_level(library: Object):
	var failures: Array = []
	var mission: Dictionary = library.get_mission("morningRoutine")
	if mission.is_empty():
		return ["mission 'morningRoutine' must keep its id; it is level 'gettingDressed'"]
	if String(mission.get("levelId", "")) != "gettingDressed":
		failures.append("mission 'morningRoutine' must stay level 'gettingDressed', got '%s'"
				% String(mission.get("levelId", "")))
	if String(mission.get("chapterId", "")) != "ch3":
		failures.append("level 'gettingDressed' belongs to ch3, got '%s'"
				% String(mission.get("chapterId", "")))
	return failures
