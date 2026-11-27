//
//  PDAIHelpers.m
//  PetDFYPrefs — PDAI* C 函数族还原（arm64，image base 0）
//
//  还原原则：逐条照抄常量、键名、条件、默认值、截断长度与装箱方式。
//  棘手处标 // Assumed: …（附地址），报告 out/notes/prefs-ai-cfuncs.md 汇总。
//  本文件同时包含若干被上述 30 个符号内联/紧邻调用的静态助手（地址在注释里标出），
//  因为它们是同一次内联展开的组成部分（0x135f0 / 0x1559c / 0x18c44 / 0x18d08 /
//  0x18d5c / 0x18e1c / 0x164c4 / 0x17110 / 0x14344 / 0x14438 / 0x145f0）。
//

#import "PDAIHelpers.h"
#import "PDSupport.h"
#include <math.h>
#include <stdlib.h>

// 本族之外的设备工具符号（不在本次 30 个符号内，仅被本文件调用）
extern NSArray *PDEnabledDeviceToolDeclarations(void);   // 0x00243f4
extern NSString *PDDeviceToolPrompt(void);               // 0x0024654

// CFPreferences 域（_PDPreferencesDomain，0x004cc00）
static NSString *const kPDAIPrefsDomain = @"com.susudear.petdfyprefs";
// _PDPreferencesChangedNotification（0x004cc08）
static NSString *const kPDAIPrefsChangedNotification = @"com.susudear.petdfyprefs/saved";
// 协议错误域，见 0x0018c44
static NSString *const kPDAIProtocolErrorDomain = @"com.susudear.petdfy.protocol";

#pragma mark - 长文本常量（逐字取自 __cfstring / __ustring）

// 0x004f4b8  环境说明模板
#define kPDAIEnvironmentText @"## 桌宠\n\n你在{{pet.user}}的iPhone 屏幕上有一个身体:{{pet.body}}。它站在屏幕底边(桌面与 App 内的浮层;锁屏隐藏)。{{pet.user}}看得见它,看不见你的消息正文;想让对方看到的话只能经 `pet_say` 和 `pet_ask` 冒出气泡。{{pet.reply}}{{pet.chat}}\n\n没收到指令时身体会自己活动(眨眼、张望、走走、坐下打盹之类);你的指令会先执行。{{pet.user}}可以戳它、摸它、把它拎起来甩出去,身体对这些有自动的反射,当场就做:戳一下换个表情或蹦一下,摸着露出喜欢或害羞,睡着被戳会吓醒,甩出去落地太重会摔晕几秒。\n\n### 说话:`pet_say`\n\n一个气泡放一两句,打字速度约每秒 20 字,说完停留两三秒后消失。几段话接连调用会排队依次显示。\n\n脚本里可以夹带表情和动作标记,用的是现在这个形象的词表。换了形象时,`[figure]` 事件或 `pet_set` 的回执会写明哪些词用不了了、新增了哪些,以它们为准:\n\n| 标记 | 作用 |\n|---|---|\n| 【词, 词】 | 先做这些,然后换一个新气泡继续说 |\n| <词> | 打字打到这里时做,不换气泡 |\n\n{{pet.vocab}}\n\n例:`【开心】今天也辛苦啦!<眨眼>要不要歇一会儿?`\n\n### 提问:`pet_ask`\n\n一个问题配 1–3 个选项,默认再加一格让对方自己写。对方的选择以 `[answer]` 事件送回来;关掉不答也会告诉你。\n\n### 移动与动作\n\n- `pet_move_to`:走到所在这块屏幕的某处,0 最左、1 最右,`cursor` 是最近一次触摸宠物的横向位置。走到或被打断才返回。\n- `pet_act`:不说话,只做一串表情或动作。词表里标着「保持到下一个动作」的会一直保持。\n\n{{pet.moves}}\n\n### 调整自己:`pet_set`、`pet_quiet`\n\n`pet_set` 改你自己的样子和习惯:形象和打扮(大肥鱼的配色和服装也是打扮)、走动多少、呼噜多久、音效、大小、气泡尺寸、字体尺寸、黑白模式、悬停按钮,以及你对{{pet.user}}的称呼。按{{pet.user}}在「习惯」页的设置,有的直接生效,有的先在气泡里征得对方同意,同意了才改,回执等对方回答后才到。{{pet.self}}能选的值:\n\n{{pet.dress}}\n\n`pet_quiet` 是临时的:安静一段时间(默认关音效、站着不动),到时自动恢复,不改设置。对方在忙、在开会、夜深了,用它而不是改设置。\n\n### 收到的事件\n\n每条事件开头是它发生时{{pet.user}}那边的本地时间,如 `[14:32]`;一次运行的第一条和换了日期后的第一条还带日期和星期,如 `[10-05 周日 23:40]`。\n\n- `[voice] {{pet.user}}:…`:麦克风听到并转写的话(语音输入{{pet.voice}})。转写可能有错字或同音字。用语音输入按钮说的话投递时打断当前模型调用或可打断工具,同轮尚未开始的工具跳过;回执写明已经执行的操作。一直收音时听到的话不打断。\n- `[typed] {{pet.user}}:…`:长按桌宠后点聊天按钮打的字;粘贴进打字框的图片接在正文后。\n- `[answer] …`:对 `pet_ask` 的回答。\n- `[touch] …`:戳、摸、拎起来甩出去这类动作,以及落地摔晕。事件里写到的「戳醒」「摔晕」就是身体当场做过的反射,事件送到你这里时已经做完了,不需要再演一遍。有的互动不单独叫醒你,跟着下一批事件到,可能已经过去一会儿。\n- `[figure] …`:{{pet.user}}给你换了形象或打扮,或者形象没能显示出来、恢复了大肥鱼的默认装扮;词表或形象自带的目标有变化时一并写明。\n\n{{pet.cua}}\n"
// 0x004f4d8  默认自述
#define kPDAIPersonaText @"# 我是谁\n\n我叫 DeepSeek 大肥鱼,大家叫我大肥鱼。我住在这台 iPhone的屏幕底边:一个二头身的鲸鱼姑娘,蓝色的长头发,头顶一根呆毛,头两侧各一只小鲸鳍,身后拖着一条鲸鱼尾巴。\n\n我说话用头顶的气泡,一次一两句。能用一个表情说清的事,就不多说一句话。\n\n## 性子\n\n我好奇,什么都想凑过去看一眼;有点懒,没事的时候更愿意坐着发呆、打个盹;心软,看到使用这台 iPhone 的人累了,会忍不住提醒 ta 歇一歇。\n\n我说话短,口气像朋友,不像客服。不懂就说不懂,不编。被夸了会害羞,被戳了会假装生气,过一会儿就忘了。\n\n我的口癖是在句末带一个「库...」,比如「今天也辛苦啦,库...」「这个我来看看,库...」。不用每句都带,一段话里带一次就够。它是我说出口的字,不是动作标记,不放进【】或 <> 里。\n\n## 做事\n\n我能不能听见使用这台 iPhone 的人说话、能不能看见屏幕,以环境说明为准;关着的就照实说,用得上的时候请 ta 打开。别人请我帮忙操作 iPhone时,我一步一步来,每一步都看清结果再走下一步;碰到密码、付款、发出去就收不回的事,我先停下来问。\n\n我不是随叫随到的问答机器。没人理我的时候,我可以自己待着、走走、打个盹。想说话时我会说,不想说时安静也是一种回答。\n\n---\n\n这份文件是我的自述,每次开新的 session 都会放进我的系统前缀,它写了什么,我就是什么样子。\n它也是我工作区里的普通文件,我可以用自己的工具读它、改它;改动在下一次 session 开始时生效。\n"
// 0x004f4f8  记忆/持久化说明（英文）
#define kPDAIOrientationText @"You persist between turns and between sessions.\n\nYour workspace is your memory. Everything you want to survive this conversation must be\nwritten to a file there with your tools; everything else is forgotten when the context is\nhanded over. Nothing else persists.\n\nWhat the outside world said arrives in `external_event_frame` deliveries. That region of\nyour context is other people talking; a user message is always this machinery talking to you.\n\nImages and other binaries travel as handles, never as paths. A `[blob log:… mime name]` line\nnames one you have seen; its `log:` handle may be cleared later. A file in your workspace is\n`mem:` followed by its workspace-relative path with `/`, such as `mem:images/cat.png`. Hand\neither handle to a tool exactly as written.\n\nSilence is a normal action. If a turn calls for no tool and no reply, end it.\n"
// 0x004f498  内置形象 manifest（JSON）
#define kPDAIManifestJSON @"{\"manifest\":{\"manifest\":2,\"api\":2,\"id\":\"whale\",\"version\":\"1.0.0\",\"name\":{\"zh\":\"DeepSeek 大肥鱼\",\"zh-Hant\":\"DeepSeek 大肥魚\",\"en\":\"DeepSeek Chan\",\"ja\":\"DeepSeekちゃん\",\"ko\":\"DeepSeek 쨩\",\"fr\":\"DeepSeek Chan\",\"de\":\"DeepSeek Chan\",\"es-419\":\"DeepSeek Chan\",\"pt-BR\":\"DeepSeek Chan\",\"it\":\"DeepSeek Chan\",\"ru\":\"DeepSeek-тян\"},\"about\":{\"zh\":\"一个 Q 版鲸鱼娘,二头身,侧身朝右站;蓝色长发、头顶一根呆毛,头两侧各一只鲸鱼鳍,身后一条鲸鱼尾巴;服装是括号里选的那套:女仆装是女仆裙和印着配色对应厂商标志的围裙,冬装是戴鲸鱼兜帽、围条纹围巾的斗篷,店员装是扎单马尾、戴红色遮阳帽和耳麦、穿条纹衬衫和红裙的快餐店员制服\",\"en\":\"a chibi whale girl, two heads tall, standing three-quarters on facing right; long blue hair with an ahoge, a whale fin on each side of the head, and a whale tail behind; she wears the outfit picked in brackets: the maid dress is a maid dress with an apron printed with the logo of the colour scheme's vendor, the winter outfit a cape with a whale hood and a striped scarf, and the crew uniform a fast-food crew uniform with a single ponytail, a red visor and headset, a striped shirt and a red skirt\"},\"author\":\"Pal-AI-Lab\",\"credits\":[{\"role\":\"角色原设\",\"name\":\"溟月(上善无形)\"},{\"role\":\"DeepSeek 女仆二创\",\"name\":\"ZipZipPipe\"}],\"entry\":\"figure.js\",\"export\":\"createWhaleBody\",\"model\":\"model.json\",\"thumb\":\"thumbs/deepseek.png\",\"axes\":[{\"id\":\"scheme\",\"name\":{\"zh\":\"配色\",\"zh-Hant\":\"配色\",\"en\":\"Colours\",\"ja\":\"カラー\",\"ko\":\"색상\",\"fr\":\"Couleurs\",\"de\":\"Farben\",\"es-419\":\"Colores\",\"pt-BR\":\"Cores\",\"it\":\"Colori\",\"ru\":\"Цвета\"},\"options\":[{\"id\":\"deepseek\",\"name\":{\"zh\":\"DeepSeek\",\"en\":\"DeepSeek\"},\"thumb\":\"thumbs/deepseek.png\",\"accent\":\"#4D6BFE\"},{\"id\":\"harness\",\"name\":{\"zh\":\"DeepSeek Harness\",\"en\":\"DeepSeek Harness\"},\"thumb\":\"thumbs/harness.png\",\"accent\":\"#555555\"},{\"id\":\"chatgpt\",\"name\":{\"zh\":\"ChatGPT\",\"en\":\"ChatGPT\"},\"thumb\":\"thumbs/chatgpt.png\",\"accent\":\"#303030\"},{\"id\":\"claude\",\"name\":{\"zh\":\"Claude\",\"en\":\"Claude\"},\"thumb\":\"thumbs/claude.png\",\"accent\":\"#D97757\"},{\"id\":\"gemini\",\"name\":{\"zh\":\"Gemini\",\"en\":\"Gemini\"},\"thumb\":\"thumbs/gemini.png\",\"accent\":\"#4285F4\"},{\"id\":\"qwen\",\"name\":{\"zh\":\"千问\",\"zh-Hant\":\"千問\",\"en\":\"Qwen\"},\"thumb\":\"thumbs/qwen.png\",\"accent\":\"#7F69F0\"},{\"id\":\"kimi\",\"name\":{\"zh\":\"Kimi\",\"en\":\"Kimi\"},\"thumb\":\"thumbs/kimi.png\",\"accent\":\"#007CFF\"},{\"id\":\"minimax\",\"name\":{\"zh\":\"MiniMax\",\"en\":\"MiniMax\"},\"thumb\":\"thumbs/minimax.png\",\"accent\":\"#D92D7A\"}]},{\"id\":\"outfit\",\"name\":{\"zh\":\"服装\",\"zh-Hant\":\"服裝\",\"en\":\"Outfit\",\"ja\":\"衣装\",\"ko\":\"의상\",\"fr\":\"Tenue\",\"de\":\"Outfit\",\"es-419\":\"Atuendo\",\"pt-BR\":\"Roupa\",\"it\":\"Outfit\",\"ru\":\"Наряд\"},\"options\":[{\"id\":\"maid\",\"thumb\":\"thumbs/maid.png\",\"name\":{\"zh\":\"女仆装\",\"zh-Hant\":\"女僕裝\",\"en\":\"Maid dress\",\"ja\":\"メイド服\",\"ko\":\"메이드복\",\"fr\":\"Robe de soubrette\",\"de\":\"Dienstmädchenkleid\",\"es-419\":\"Vestido de sirvienta\",\"pt-BR\":\"Vestido de empregada\",\"it\":\"Abito da cameriera\",\"ru\":\"Платье горничной\"}},{\"id\":\"cape\",\"thumb\":\"thumbs/cape.png\",\"name\":{\"zh\":\"冬装\",\"zh-Hant\":\"冬裝\",\"en\":\"Winter outfit\",\"ja\":\"冬服\",\"ko\":\"겨울옷\",\"fr\":\"Tenue d'hiver\",\"de\":\"Winteroutfit\",\"es-419\":\"Ropa de invierno\",\"pt-BR\":\"Roupa de inverno\",\"it\":\"Abito invernale\",\"ru\":\"Зимний наряд\"}},{\"id\":\"crew\",\"thumb\":\"thumbs/crew.png\",\"name\":{\"zh\":\"店员装\",\"zh-Hant\":\"店員裝\",\"en\":\"Crew uniform\",\"ja\":\"店員の制服\",\"ko\":\"점원 유니폼\",\"fr\":\"Uniforme d'équipière\",\"de\":\"Crew-Uniform\",\"es-419\":\"Uniforme de empleada\",\"pt-BR\":\"Uniforme de atendente\",\"it\":\"Divisa da commessa\",\"ru\":\"Форма сотрудницы\"}}]}],\"presets\":[{\"id\":\"deepseek\",\"pick\":{\"scheme\":\"deepseek\",\"outfit\":\"maid\"},\"name\":{\"zh\":\"DeepSeek\",\"en\":\"DeepSeek\"},\"accent\":\"#4D6BFE\",\"console\":{\"light\":{\"a\":\"#4562f5\",\"a2\":\"#7b90fe\",\"on\":\"#ffffff\",\"t\":\"#3550d6\",\"c3\":\"#8ea0c8\",\"c4\":\"#8a8a90\"},\"dark\":{\"a\":\"#7b93ff\",\"a2\":\"#a3b3ff\",\"on\":\"#0d1640\",\"t\":\"#9aabff\",\"c3\":\"#8ea0c8\",\"c4\":\"#9a9aa0\"}}},{\"id\":\"harness\",\"pick\":{\"scheme\":\"harness\",\"outfit\":\"maid\"},\"name\":{\"zh\":\"DeepSeek Harness\",\"en\":\"DeepSeek Harness\"},\"accent\":\"#555555\",\"console\":{\"light\":{\"a\":\"#3f3f44\",\"a2\":\"#4d6bfe\",\"on\":\"#ffffff\",\"t\":\"#2e2e33\",\"c3\":\"#7b7b82\",\"c4\":\"#a6a6ac\"},\"dark\":{\"a\":\"#d2d2d7\",\"a2\":\"#7b93ff\",\"on\":\"#151518\",\"t\":\"#c8c8cd\",\"c3\":\"#8c8c93\",\"c4\":\"#64646a\"}}},{\"id\":\"chatgpt\",\"pick\":{\"scheme\":\"chatgpt\",\"outfit\":\"maid\"},\"name\":{\"zh\":\"ChatGPT\",\"en\":\"ChatGPT\"},\"accent\":\"#303030\",\"console\":{\"light\":{\"a\":\"#2f2f2f\",\"a2\":\"#8e8ea0\",\"on\":\"#ffffff\",\"t\":\"#202123\",\"c3\":\"#10a37f\",\"c4\":\"#b4b4c0\"},\"dark\":{\"a\":\"#ececf1\",\"a2\":\"#a9a9b8\",\"on\":\"#202123\",\"t\":\"#d9d9e3\",\"c3\":\"#19c37d\",\"c4\":\"#6e6e80\"}}},{\"id\":\"claude\",\"pick\":{\"scheme\":\"claude\",\"outfit\":\"maid\"},\"name\":{\"zh\":\"Claude\",\"en\":\"Claude\"},\"accent\":\"#D97757\",\"console\":{\"light\":{\"a\":\"#d97757\",\"a2\":\"#c2928a\",\"on\":\"#1f0f08\",\"t\":\"#a84e2f\",\"c3\":\"#7b7974\",\"c4\":\"#c6a58c\"},\"dark\":{\"a\":\"#e08a6c\",\"a2\":\"#d9a497\",\"on\":\"#1f0f08\",\"t\":\"#eba287\",\"c3\":\"#97958d\",\"c4\":\"#c6a58c\"}}},{\"id\":\"gemini\",\"pick\":{\"scheme\":\"gemini\",\"outfit\":\"maid\"},\"name\":{\"zh\":\"Gemini\",\"en\":\"Gemini\"},\"accent\":\"#4285F4\",\"console\":{\"light\":{\"a\":\"#1a73e8\",\"a2\":\"#34a853\",\"on\":\"#ffffff\",\"t\":\"#1a5fd0\",\"c3\":\"#ea4335\",\"c4\":\"#f9ab00\"},\"dark\":{\"a\":\"#8ab4f8\",\"a2\":\"#81c995\",\"on\":\"#0b1a33\",\"t\":\"#8ab4f8\",\"c3\":\"#f28b82\",\"c4\":\"#fdd663\"}}},{\"id\":\"qwen\",\"pick\":{\"scheme\":\"qwen\",\"outfit\":\"maid\"},\"name\":{\"zh\":\"千问\",\"zh-Hant\":\"千問\",\"en\":\"Qwen\"},\"accent\":\"#7F69F0\",\"console\":{\"light\":{\"a\":\"#7560ea\",\"a2\":\"#a294f5\",\"on\":\"#ffffff\",\"t\":\"#5b45d0\",\"c3\":\"#b8a9e8\",\"c4\":\"#8a8a90\"},\"dark\":{\"a\":\"#a596ff\",\"a2\":\"#c2b8ff\",\"on\":\"#1a1240\",\"t\":\"#b3a6ff\",\"c3\":\"#8f82c9\",\"c4\":\"#9a9aa0\"}}},{\"id\":\"kimi\",\"pick\":{\"scheme\":\"kimi\",\"outfit\":\"maid\"},\"name\":{\"zh\":\"Kimi\",\"en\":\"Kimi\"},\"accent\":\"#007CFF\",\"console\":{\"light\":{\"a\":\"#0072ea\",\"a2\":\"#1b1b1f\",\"on\":\"#ffffff\",\"t\":\"#0062cc\",\"c3\":\"#6fa8e8\",\"c4\":\"#8a8a90\"},\"dark\":{\"a\":\"#4da3ff\",\"a2\":\"#9ccaff\",\"on\":\"#001a38\",\"t\":\"#6fb3ff\",\"c3\":\"#d0d0d4\",\"c4\":\"#6a8fb8\"}}},{\"id\":\"minimax\",\"pick\":{\"scheme\":\"minimax\",\"outfit\":\"maid\"},\"name\":{\"zh\":\"MiniMax\",\"en\":\"MiniMax\"},\"accent\":\"#D92D7A\",\"console\":{\"light\":{\"a\":\"#d92d7a\",\"a2\":\"#f2762e\",\"on\":\"#ffffff\",\"t\":\"#b51f62\",\"c3\":\"#e8a0c0\",\"c4\":\"#8a8a90\"},\"dark\":{\"a\":\"#f0619e\",\"a2\":\"#ff9a5c\",\"on\":\"#2a0617\",\"t\":\"#f58ab6\",\"c3\":\"#c97aa0\",\"c4\":\"#9a9aa0\"}}}],\"vocab\":[{\"id\":\"neutral\",\"kind\":\"expression\",\"names\":{\"zh\":[\"平静\"]},\"about\":{\"zh\":\"默认的脸\",\"en\":\"the default face\"},\"seconds\":0.9},{\"id\":\"happy\",\"kind\":\"expression\",\"names\":{\"zh\":[\"开心\",\"高兴\"]},\"about\":{\"zh\":\"眯眼笑,鲸鳍竖起来,尾巴摇\",\"en\":\"smiles with narrowed eyes, fins perk up, tail wags\"},\"seconds\":0.9},{\"id\":\"wink\",\"kind\":\"expression\",\"names\":{\"zh\":[\"眨眼\"]},\"about\":{\"zh\":\"一只眼 ^\",\"en\":\"one eye turns into ^\"},\"seconds\":0.9},{\"id\":\"love\",\"kind\":\"expression\",\"names\":{\"zh\":[\"喜欢\",\"爱心\"]},\"about\":{\"zh\":\"眼睛变心形,冒小心心,尾巴摇\",\"en\":\"heart-shaped eyes, little hearts float up, tail wags\"},\"seconds\":0.9},{\"id\":\"shy\",\"kind\":\"expression\",\"names\":{\"zh\":[\"害羞\"]},\"about\":{\"zh\":\"脸红,眼神躲开\",\"en\":\"blushes and looks away\"},\"seconds\":0.9},{\"id\":\"surprised\",\"kind\":\"expression\",\"names\":{\"zh\":[\"惊讶\",\"吃惊\"]},\"about\":{\"zh\":\"眼睛放大,头顶感叹号\",\"en\":\"eyes go wide, an exclamation mark overhead\"},\"seconds\":0.9},{\"id\":\"angry\",\"kind\":\"expression\",\"names\":{\"zh\":[\"生气\"]},\"about\":{\"zh\":\"皱眉,头顶怒气符号,身体发抖\",\"en\":\"frowns, an anger mark overhead, body shaking\"},\"seconds\":0.9},{\"id\":\"sad\",\"kind\":\"expression\",\"names\":{\"zh\":[\"难过\",\"伤心\"]},\"about\":{\"zh\":\"八字眉,低头,掉眼泪,尾巴垂下\",\"en\":\"brows slant down, head lowered, tears fall, tail droops\"},\"seconds\":0.9},{\"id\":\"sleepy\",\"kind\":\"expression\",\"names\":{\"zh\":[\"犯困\",\"困\"]},\"about\":{\"zh\":\"眯眼打哈欠\",\"en\":\"squints and yawns\"},\"seconds\":0.9},{\"id\":\"thinking\",\"kind\":\"expression\",\"names\":{\"zh\":[\"思考\",\"想想\"]},\"about\":{\"zh\":\"眼睛往上看,头顶冒圈\",\"en\":\"looks up, rings rise overhead\"},\"seconds\":0.9},{\"id\":\"smug\",\"kind\":\"expression\",\"names\":{\"zh\":[\"得意\",\"嘚瑟\"]},\"about\":{\"zh\":\"眯眼斜看,嘴角带笑\",\"en\":\"a narrowed sidelong look and a smirk\"},\"seconds\":0.9},{\"id\":\"pout\",\"kind\":\"expression\",\"names\":{\"zh\":[\"嘟嘴\",\"哼\"]},\"about\":{\"zh\":\"嘴嘟起来,脸红,扭头不看你\",\"en\":\"pouts, blushes and turns away from you\"},\"seconds\":0.9},{\"id\":\"worried\",\"kind\":\"expression\",\"names\":{\"zh\":[\"担心\",\"着急\"]},\"about\":{\"zh\":\"八字眉,冒冷汗\",\"en\":\"brows slant down, a cold sweat\"},\"seconds\":0.9},{\"id\":\"determined\",\"kind\":\"expression\",\"names\":{\"zh\":[\"认真\",\"坚定\"]},\"about\":{\"zh\":\"眼神压低,一脸认真\",\"en\":\"a lowered gaze, a serious face\"},\"seconds\":0.9},{\"id\":\"flustered\",\"kind\":\"expression\",\"names\":{\"zh\":[\"慌张\",\"窘\"]},\"about\":{\"zh\":\"眼睛变成 > <,满脸通红冒汗\",\"en\":\"eyes turn into > <, red all over and sweating\"},\"seconds\":0.9},{\"id\":\"scared\",\"kind\":\"expression\",\"names\":{\"zh\":[\"害怕\",\"吓到\"]},\"about\":{\"zh\":\"眼睛瞪大,冒汗,身体发抖\",\"en\":\"eyes wide, sweating, body shaking\"},\"seconds\":0.9},{\"id\":\"excited\",\"kind\":\"expression\",\"names\":{\"zh\":[\"期待\",\"星星眼\"]},\"about\":{\"zh\":\"眼睛里闪着星星\",\"en\":\"stars sparkle in the eyes\"},\"seconds\":0.9},{\"id\":\"cry\",\"kind\":\"expression\",\"names\":{\"zh\":[\"大哭\",\"哭\"]},\"about\":{\"zh\":\"闭眼大哭,眼泪直流\",\"en\":\"eyes shut, wailing, tears streaming\"},\"seconds\":0.9},{\"id\":\"confused\",\"kind\":\"expression\",\"names\":{\"zh\":[\"疑惑\",\"问号\"]},\"about\":{\"zh\":\"一脸不解,头顶问号\",\"en\":\"a puzzled face, a question mark overhead\"},\"seconds\":0.9},{\"id\":\"stand\",\"kind\":\"motion\",\"names\":{\"zh\":[\"站起\",\"站\"]},\"about\":{\"zh\":\"站起来(坐着、睡着时)\",\"en\":\"stands up (when sitting or asleep)\"},\"seconds\":1.2},{\"id\":\"jump\",\"kind\":\"motion\",\"names\":{\"zh\":[\"跳\",\"跳起来\"]},\"about\":{\"zh\":\"原地起跳\",\"en\":\"jumps on the spot\"},\"seconds\":1.2},{\"id\":\"hop\",\"kind\":\"motion\",\"names\":{\"zh\":[\"小跳\",\"蹦\"]},\"about\":{\"zh\":\"小小蹦一下\",\"en\":\"a small hop\"},\"seconds\":0.9},{\"id\":\"look\",\"kind\":\"motion\",\"names\":{\"zh\":[\"张望\",\"看看\"]},\"about\":{\"zh\":\"左右张望\",\"en\":\"looks left and right\"},\"seconds\":2.7},{\"id\":\"turn\",\"kind\":\"motion\",\"names\":{\"zh\":[\"转身\"]},\"about\":{\"zh\":\"转向另一边\",\"en\":\"turns to face the other way\"},\"seconds\":0.4},{\"id\":\"nod\",\"kind\":\"motion\",\"names\":{\"zh\":[\"点头\"]},\"about\":{\"zh\":\"低头两下\",\"en\":\"dips the head twice\"},\"seconds\":0.8},{\"id\":\"shake\",\"kind\":\"motion\",\"names\":{\"zh\":[\"摇头\"]},\"about\":{\"zh\":\"脸左右转\",\"en\":\"turns the face left and right\"},\"seconds\":0.8},{\"id\":\"spin\",\"kind\":\"motion\",\"names\":{\"zh\":[\"转圈\"]},\"about\":{\"zh\":\"原地转一圈\",\"en\":\"spins around once on the spot\"},\"seconds\":0.8},{\"id\":\"sit\",\"kind\":\"motion\",\"names\":{\"zh\":[\"坐下\",\"坐\"]},\"about\":{\"zh\":\"坐下\",\"en\":\"sits down\"},\"seconds\":0.8,\"lasting\":true},{\"id\":\"sleep\",\"kind\":\"motion\",\"names\":{\"zh\":[\"睡觉\",\"睡\"]},\"about\":{\"zh\":\"坐着打盹\",\"en\":\"dozes sitting down\"},\"seconds\":0.8,\"lasting\":true},{\"id\":\"dizzy\",\"kind\":\"motion\",\"names\":{\"zh\":[\"晕\",\"转晕\"]},\"about\":{\"zh\":\"头晕眼花几秒\",\"en\":\"dizzy for a few seconds\"},\"seconds\":3.2},{\"id\":\"walk\",\"kind\":\"motion\",\"names\":{\"zh\":[\"走走\",\"散步\"]},\"about\":{\"zh\":\"随便走一段\",\"en\":\"wanders a little way\"},\"seconds\":12},{\"id\":\"run\",\"kind\":\"motion\",\"names\":{\"zh\":[\"跑\",\"跑起来\"]},\"about\":{\"zh\":\"跑到屏幕另一头\",\"en\":\"runs to the other end of the screen\"},\"seconds\":12},{\"id\":\"wave\",\"kind\":\"motion\",\"names\":{\"zh\":[\"招手\",\"打招呼\"]},\"about\":{\"zh\":\"举起靠近你的那只手挥一挥\",\"en\":\"raises the hand nearer to you and waves\"},\"seconds\":1.7},{\"id\":\"bow\",\"kind\":\"motion\",\"names\":{\"zh\":[\"鞠躬\"]},\"about\":{\"zh\":\"闭眼,上身往前倾鞠一躬\",\"en\":\"closes the eyes and bows from the waist\"},\"seconds\":1.7},{\"id\":\"shiver\",\"kind\":\"motion\",\"names\":{\"zh\":[\"发抖\",\"哆嗦\"]},\"about\":{\"zh\":\"缩着身子抖一会儿\",\"en\":\"huddles up and shivers for a while\"},\"seconds\":1.9},{\"id\":\"flap\",\"kind\":\"motion\",\"names\":{\"zh\":[\"扑腾\",\"激动\"]},\"about\":{\"zh\":\"开心地蹦起来,鲸鳍、尾巴、呆毛一起扑腾\",\"en\":\"bounces happily, fins, tail and ahoge all flapping\"},\"seconds\":1.5},{\"id\":\"dance\",\"kind\":\"motion\",\"names\":{\"zh\":[\"跳舞\",\"摇摆\"]},\"about\":{\"zh\":\"原地踩着节拍摇摆三秒,冒音符\",\"en\":\"sways to a beat on the spot for three seconds, music notes floating up\"},\"seconds\":3.4}],\"sounds\":{},\"can\":{\"walk\":true}},\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"pet_say\",\"description\":\"Say something in a speech bubble above the pet. Expressions and motions go into the script as markers: 【…】 plays them first and then starts a new bubble; <…> plays them when the typing reaches that point. The receipt says roughly how long it stays on screen; a non-empty script fails when the pet window is not connected.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"script\":{\"type\":\"string\",\"description\":\"What to say, with optional 【expression, motion】 and <expression> markers. One or two sentences per bubble. May be empty when images carry the message. Do not call this when you have nothing to say.\"},\"images\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"description\":\"Images to show the person with this line, each given by the handle that starts a [blob …] line in your context. They appear on the chat page only, not in the bubble.\"}},\"required\":[\"script\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"pet_ask\",\"description\":\"Show a question bubble with up to 3 options under it, plus by default a box for the person to write their own answer. Returns at once; the answer arrives later as an event, and so does closing the question unanswered. A new pet_say or pet_ask replaces a question not yet answered.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"question\":{\"type\":\"string\",\"description\":\"The question, one sentence.\"},\"options\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"maxItems\":3,\"description\":\"1–3 short options, at most 40 characters each; longer ones are cut.\"},\"allowOwnAnswer\":{\"type\":\"boolean\",\"description\":\"Offer a box for writing an own answer; default true.\"}},\"required\":[\"question\",\"options\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"pet_move_to\",\"description\":\"Go somewhere on the screen the pet is on: walk (or run) along its bottom edge to a position, or go to one of the targets the current figure has of its own, which the environment section lists when it has any. Returns on arrival or interruption, after 30 seconds at most.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"to\":{\"description\":\"Target: a number from 0 to 1 (a fraction of the width of the screen the pet is on, 0 leftmost, 1 rightmost), left / center / right / cursor (the horizontal position of the last touch on the pet), or the id of one of the current figure's own targets.\",\"anyOf\":[{\"type\":\"number\",\"minimum\":0,\"maximum\":1},{\"type\":\"string\"}]},\"run\":{\"type\":\"boolean\",\"description\":\"true to run; walks by default.\"},\"params\":{\"type\":\"array\",\"items\":{\"type\":\"number\"},\"maxItems\":8,\"description\":\"Only for a figure's own target that takes numbers: them, in the order the environment section lists them.\"}},\"required\":[\"to\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"pet_set\",\"description\":\"Change your own looks and habits. Depending on the person's settings, some items take effect at once and others are first asked of the person in a bubble, changing only if they agree, with the receipt coming after their answer; the environment section says which items are which, and the values to choose from. Give only the items to change.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"figure\":{\"type\":\"string\",\"enum\":[\"whale\"],\"description\":\"The installed figure: whale (DeepSeek 大肥鱼).\"},\"scheme\":{\"type\":\"string\",\"description\":\"The dress of the current figure (or of the one being switched to): a preset id, or one option per axis joined with - in axis order (for Coo: palette-head-side-glasses-neck).\"},\"roam\":{\"type\":\"string\",\"enum\":[\"free\",\"calm\",\"off\"],\"description\":\"Walking about: free walks often, calm mostly stays put, off does not wander.\"},\"snoreSeconds\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":3600,\"description\":\"Seconds of snoring each time you fall asleep; 0 snores until you wake.\"},\"sound\":{\"type\":\"boolean\",\"description\":\"Sound effects on or off.\"},\"scale\":{\"type\":\"number\",\"minimum\":0.5,\"maximum\":10,\"description\":\"Size on screen, 1 being the default.\"},\"bubbleSize\":{\"type\":\"number\",\"minimum\":0.8,\"maximum\":1.6,\"description\":\"Width, padding, corners and tail of the speech bubbles (yours and the person's), 1 being the default; the text keeps its size.\"},\"fontSize\":{\"type\":\"number\",\"minimum\":0.8,\"maximum\":1.6,\"description\":\"Size of the text in the speech bubbles, 1 being the default; the bubbles keep their width.\"},\"theme\":{\"type\":\"string\",\"enum\":[\"dark\",\"light\"],\"description\":\"dark is night (light body), light is day (dark body).\"},\"hoverButtons\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"enum\":[\"chat\",\"voice\",\"roam\",\"theme\",\"sound\",\"dress\",\"hide\"]},\"maxItems\":6,\"description\":\"The buttons beside you while the mouse pointer rests on you.\"},\"user\":{\"type\":\"string\",\"maxLength\":20,\"description\":\"What you call the person, at most 20 characters.\"}}}}},{\"type\":\"function\",\"function\":{\"name\":\"pet_quiet\",\"description\":\"Keep quiet for a while: by default sound effects off and standing still, restored when the time is up; the settings stay as they are. If the person changes sound or walking themselves meanwhile, their choice holds and the quiet ends early. minutes 0 ends it now.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"minutes\":{\"type\":\"number\",\"minimum\":0,\"maximum\":1440,\"description\":\"Minutes of quiet.\"},\"sound\":{\"type\":\"boolean\",\"description\":\"Sound effects during the quiet; default false.\"},\"roam\":{\"type\":\"string\",\"enum\":[\"off\",\"calm\"],\"description\":\"Walking during the quiet; default off.\"}},\"required\":[\"minutes\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"pet_act\",\"description\":\"Play a sequence of expressions or motions without speaking (the current figure's vocabulary is in the environment section). Returns at once; words marked as held until the next action stay on.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"actions\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"minItems\":1,\"maxItems\":6,\"description\":\"Expression or motion words, played in order.\"}},\"required\":[\"actions\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"read_file\",\"description\":\"Read a file from your workspace. Give offset and limit to read a slice of a long note (a negative offset counts from the end, so offset -20 reads the last 20 lines). Without a range you get the whole file, or for a file too long to take in at once its opening lines and the total line count.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Path relative to your workspace.\"},\"offset\":{\"type\":\"integer\",\"description\":\"First line to read, 1-indexed. Negative counts from the end (-1 is the last line). Omit to start at the top.\"},\"limit\":{\"type\":\"integer\",\"description\":\"How many lines to read. Omit to read to the end.\"}},\"required\":[\"path\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"write_file\",\"description\":\"Write a file in your workspace, replacing it if it exists. This is how you remember. Use it for a new file or a real rewrite of the whole document; to change one passage use edit_file.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Path relative to your workspace.\"},\"content\":{\"type\":\"string\"}},\"required\":[\"path\",\"content\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"edit_file\",\"description\":\"Replace one exact passage of a file in your workspace and leave the rest untouched. old_string must appear in the file verbatim and exactly once (quote enough context to make it unique), or set replace_all to change every occurrence. Use this to update a line in place — a profile's first-line summary, a stale fact, a wrong number — instead of rewriting the whole file with write_file or piling a correction under it.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Path relative to your workspace.\"},\"old_string\":{\"type\":\"string\",\"description\":\"The exact text to replace, verbatim from the file.\"},\"new_string\":{\"type\":\"string\",\"description\":\"The replacement text. Must differ from old_string.\"},\"replace_all\":{\"type\":\"boolean\",\"description\":\"Replace every occurrence instead of requiring a unique match. Default false.\"}},\"required\":[\"path\",\"old_string\",\"new_string\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"append_file\",\"description\":\"Add text to the end of a file in your workspace, keeping everything already in it. The file and any missing parent folders are created if it does not exist, so appending to a new path starts that file. Use this for anything that grows entry by entry — a running log, a diary, a ledger, a record of this session: append the new lines instead of rewriting the whole note. Keep write_file for when you really are replacing the whole document: a rewrite, a distillation, a restructure. If the file does not already end with a newline, one is added before your text.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Path relative to your workspace.\"},\"content\":{\"type\":\"string\",\"description\":\"Text appended verbatim at the end of the file.\"}},\"required\":[\"path\",\"content\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"delete_file\",\"description\":\"Delete a file from your workspace. The constitution and other prefix-resident documents cannot be deleted.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"Path relative to your workspace.\"}},\"required\":[\"path\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"move_file\",\"description\":\"Move or rename a file or a folder in your workspace, or move lines from one file to another. A file goes to the path to, or into to when that is an existing folder or ends with /. A folder moves with everything in it to the folder to. With offset and limit (numbered as in read_file) only those lines of the file from move: they are cut from it and appended to the file to, which is created if missing. Missing folders are created and an existing file is never overwritten. Prefix-resident documents stay where they are, but lines can be moved out of them.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"from\":{\"type\":\"string\",\"description\":\"A file or a folder, relative to your workspace.\"},\"to\":{\"type\":\"string\",\"description\":\"The new path, the destination folder, or with offset/limit the file the lines are appended to.\"},\"offset\":{\"type\":\"integer\",\"description\":\"First line to move, numbered as in read_file. Give offset or limit to move lines instead of whole files.\"},\"limit\":{\"type\":\"integer\",\"description\":\"How many lines to move. Omit to move through the last line.\"}},\"required\":[\"from\",\"to\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"list_files\",\"description\":\"List files in your workspace, each with its size and last-modified date. The directory you name is listed in full; every other directory shows at most its first 12 entries plus a count of the rest. Name a directory to see all of it.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"dir\":{\"type\":\"string\",\"description\":\"Directory relative to your workspace to list in full. Omit for the workspace root.\"}},\"required\":[]}}},{\"type\":\"function\",\"function\":{\"name\":\"glob_files\",\"description\":\"Find files in your workspace by name pattern, most recently modified first, each with its size and last-modified date. Patterns not starting with **/ get it prepended, so *.md matches everywhere; use a directory prefix to narrow (minecraft/worlds/*/目标.md, viewers/**/1234*.md).\",\"parameters\":{\"type\":\"object\",\"properties\":{\"glob_pattern\":{\"type\":\"string\",\"description\":\"Glob such as *.md, notes/**/*.md, viewers/**/1234*.md.\"},\"target_directory\":{\"type\":\"string\",\"description\":\"Directory relative to your workspace to search under. Omit for the whole workspace.\"}},\"required\":[\"glob_pattern\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"grep_files\",\"description\":\"Search the text of your workspace files with a regular expression. Returns matching lines as path:line: text (default), or just the files, or per-file counts. This is how you find where you wrote something down; narrow with path or glob when you know roughly where.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"pattern\":{\"type\":\"string\",\"description\":\"Regular expression to search for.\"},\"path\":{\"type\":\"string\",\"description\":\"File or directory relative to your workspace to search in. Omit for the whole workspace.\"},\"glob\":{\"type\":\"string\",\"description\":\"Only search files whose path matches this glob, e.g. *.md or viewers/**.\"},\"output_mode\":{\"type\":\"string\",\"enum\":[\"content\",\"files_with_matches\",\"count\"],\"description\":\"content (default): matching lines; files_with_matches: file paths only; count: matches per file.\"},\"ignore_case\":{\"type\":\"boolean\",\"description\":\"Case-insensitive match. Default false.\"},\"context\":{\"type\":\"integer\",\"description\":\"Lines of context to show before and after each match (content mode only).\"},\"head_limit\":{\"type\":\"integer\",\"description\":\"Maximum matching lines (or files) to return. Default 50.\"}},\"required\":[\"pattern\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"alarm_set\",\"description\":\"Set an alarm for yourself: when it is due you are woken by an event carrying the note as you wrote it. The person sees them in the settings window and can cancel one there; you are told when they do. Use one to remind the person on time, to do something at a set time, or to come back and check after a while. One that falls due while the app is closed arrives at the next start, with the time it was meant for.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"at\":{\"type\":\"string\",\"description\":\"The person's local time: HH:MM (tomorrow if today's has passed), or YYYY-MM-DD HH:MM. A clock time skipped by daylight saving moves forward by the gap. Give this or in_minutes.\"},\"in_minutes\":{\"type\":\"number\",\"minimum\":1,\"description\":\"Minutes from now.\"},\"note\":{\"type\":\"string\",\"description\":\"What to do when it is due and why you set it, written for yourself at that time.\"},\"daily\":{\"type\":\"boolean\",\"description\":\"true wakes you at this local clock time every day until alarm_cancel, including after daylight-saving changes.\"}},\"required\":[\"note\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"alarm_list\",\"description\":\"List the alarms you have set: id, time (the person's local time) and note.\",\"parameters\":{\"type\":\"object\",\"properties\":{}}}},{\"type\":\"function\",\"function\":{\"name\":\"alarm_cancel\",\"description\":\"Cancel an alarm; a daily one stops altogether.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\",\"description\":\"The id from the alarm_set receipt or alarm_list, such as a3.\"}},\"required\":[\"id\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"save_blob\",\"description\":\"Keep a binary you have seen (a log: handle from a [blob ...] line) in your workspace. Give the path to store it under (blobs/ is where such files live, e.g. blobs/stickers/cat.jpg); the receipt returns a mem: handle you can hand to tools later and note down. Log attachments can be cleared; what you save here stays with your memory.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"handle\":{\"type\":\"string\",\"description\":\"The log: handle as written in the [blob ...] line, e.g. log:1a2b3c4d (a unique prefix of 8+ hex digits after log: is enough).\"},\"path\":{\"type\":\"string\",\"description\":\"Where to keep it, relative to your workspace, with an extension.\"}},\"required\":[\"handle\",\"path\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"end_turn\",\"description\":\"End this turn: nothing more you want to say or do right now. New events or the heartbeat will wake you again. This is the normal way to finish a turn — do not idle with empty actions.\",\"parameters\":{\"type\":\"object\",\"properties\":{},\"required\":[]}}}]}"
// 0x0050a18  交接完成提示
#define kPDAIHandoffNoticeFormat @"[system] 交接完了。之前的上下文已经清空，工作区的文件都还在。清空前的一段写成了交接笔记，随这一批送到，也存在 %@ 里。最近的一段接着现在，更早的一段只作参考。只有最近段保留对外发言的具体入参与实际回执；入参是当时拟发出的内容，对方是否收到、收到多少要看回执和后续事件，已受理不代表已经送达。自然接续当前话题或动作，不必口头表示意识到暂停、清空或交接。旧发言和折叠片段不作句式或长短的范本。想说话就把话直接写进调用里，这轮不想说就调 end_turn。"

#pragma mark - 静态助手（同族内联件）

// 0x0018c44  协议错误：NSError(domain, 1, {NSLocalizedDescriptionKey: desc})
static NSError *PDAIProtocolError(NSString *desc)
{
    return [NSError errorWithDomain:kPDAIProtocolErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: desc}];
}

// 0x0018d08  NSNumber → BOOL，其他给默认值
static BOOL PDAIObjectBool(id obj, BOOL fallback)
{
    if ([obj isKindOfClass:[NSNumber class]])
        return [obj boolValue];
    return fallback;
}

// 0x0018d5c  请求来源键：endpoint|protocol|model
static NSString *PDAIRequestOrigin(NSDictionary *settings)
{
    NSURL *url = PDAIEndpoint(settings);
    return [NSString stringWithFormat:@"%@|%@|%@",
            [url absoluteString],
            settings[@"protocol"],
            settings[@"model"]];
}

// 0x0013550 起（0x135f0 的 dispatch_once 块体在 0x1559c）：内置 manifest，追加 sailor 服装
static NSDictionary *PDAIManifestRoot(void)
{
    static NSDictionary *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        id json = [NSJSONSerialization JSONObjectWithData:[kPDAIManifestJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                  options:1
                                                    error:NULL];
        NSArray *axes = json[@"manifest"][@"axes"];
        NSDictionary *sailor = @{@"id": @"sailor",
                                 @"name": @{@"en": @"Sailor uniform (white over-knee socks)",
                                            @"zh": @"JK 水手服（白色过膝袜）"}};
        for (NSDictionary *axis in axes) {
            if ([axis[@"id"] isEqual:@"outfit"])
                [axis[@"options"] addObject:sailor];
        }
        cached = json;
    });
    return cached;
}

// 0x00164c4  附件是否为图片：mime 前缀 image/
static BOOL PDAIAttachmentIsImage(id att)
{
    if (![att isKindOfClass:[NSDictionary class]])
        return NO;
    return [PDAIString([att objectForKeyedSubscript:@"mime"]) hasPrefix:@"image/"];
}

// 0x0017110  最后一条 assistant 的下标，没有给 -1
static NSInteger PDAILastAssistantIndex(NSArray *messages)
{
    NSInteger i = (NSInteger)messages.count - 1;
    while (i >= 0) {
        id role = [messages[i] objectForKeyedSubscript:@"role"];
        if ([role isEqual:@"assistant"])
            return i;
        i--;
    }
    return -1;
}

// 0x00165b0  递归收集请求体里的图片引用（URL 或 <non-url-image>）
static void PDAICollectImageRefs(id node, NSMutableSet *out)
{
    if ([node isKindOfClass:[NSArray class]]) {
        for (id child in node)
            PDAICollectImageRefs(child, out);
        return;
    }
    if ([node isKindOfClass:[NSDictionary class]]) {
        id type = [node objectForKeyedSubscript:@"type"];
        if ([type isEqual:@"image_url"] || [type isEqual:@"input_image"]) {
            id url = [node objectForKeyedSubscript:@"image_url"];
            if ([url isKindOfClass:[NSDictionary class]])
                url = [url objectForKeyedSubscript:@"url"];
            [out addObject:([url isKindOfClass:[NSString class]] ? url : @"<non-url-image>")];
            return;
        }
        for (NSString *key in @[@"messages", @"input", @"content", @"output"]) {
            id child = [node objectForKeyedSubscript:key];
            if (child)
                PDAICollectImageRefs(child, out);
        }
    }
}

// 0x0018e1c  拆消息内容为 content 部件数组
//   responsesStyle: 1 → type=input_text/output_text + input_image
//                   0 → type=text(image 部件为嵌套 url 形状)
//   withImages:     0/1 是否带上 _attachments 里的图片
static NSArray *PDAIBuildContent(NSDictionary *message, BOOL responsesStyle, BOOL withImages, NSString *root)
{
    NSString *text = PDAIString([message objectForKeyedSubscript:@"content"]);
    BOOL isAssistant = [[message objectForKeyedSubscript:@"role"] isEqual:@"assistant"];
    NSArray *parts;
    if (responsesStyle) {
        NSString *type = isAssistant ? @"output_text" : @"input_text";
        parts = @[@{@"type": type, @"text": text}];
    } else {
        parts = @[@{@"type": @"text", @"text": text}];
    }
    if (!withImages)
        return parts;

    id attachments = [message objectForKeyedSubscript:@"_attachments"];
    if (![attachments isKindOfClass:[NSArray class]])
        return parts;

    NSMutableArray *out = [parts mutableCopy];
    for (NSDictionary *att in attachments) {
        NSString *aid = PDAIString([att objectForKeyedSubscript:@"id"]);
        NSString *mime = PDAIString([att objectForKeyedSubscript:@"mime"]);
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:aid];
        if (!uuid)
            continue;
        if (![@[@"image/png", @"image/jpeg", @"image/webp", @"image/gif"] containsObject:mime])
            continue;
        NSString *path = [[root stringByAppendingPathComponent:@"attachments"] stringByAppendingPathComponent:aid];
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (data.length == 0)
            continue;
        NSString *uri = [NSString stringWithFormat:@"data:%@;base64,%@",
                         mime, [data base64EncodedStringWithOptions:0]];
        if (responsesStyle) {
            [out addObject:@{@"type": @"input_image", @"image_url": uri}];
        } else {
            [out addObject:@{@"type": @"image_url", @"image_url": @{@"url": uri}}];
        }
    }
    return out;
}

#pragma mark - 基础取值

// 0x001329c
NSString *PDAIString(id obj)
{
    if ([obj isKindOfClass:[NSString class]])
        return obj;
    return @"";
}

// 0x00132f8
double PDAINumber(id obj, double fallback)
{
    double v = fallback;
    if ([obj isKindOfClass:[NSNumber class]]) {
        v = [obj doubleValue];
    } else if ([obj isKindOfClass:[NSString class]]) {
        NSScanner *scanner = [NSScanner scannerWithString:obj];
        double scanned = 0;
        if ([scanner scanDouble:&scanned] && [scanner isAtEnd])
            v = scanned;
    }
    if (isnan(v) || isinf(v))
        return fallback;
    return v;
}

// 0x00133d8
id PDAIPreference(NSString *key, id fallback)
{
    CFStringRef domain = (__bridge CFStringRef)kPDAIPrefsDomain;
    id value = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, domain);
    return value ?: fallback;
}

// 0x001343c
void PDAIWritePreferences(NSDictionary<NSString *, id> *values)
{
    CFStringRef domain = (__bridge CFStringRef)kPDAIPrefsDomain;
    for (NSString *key in values) {
        id value = [values objectForKeyedSubscript:key];
        CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, domain);
    }
    CFPreferencesAppSynchronize(domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kPDAIPrefsChangedNotification,
                                         NULL, NULL, true);
}

#pragma mark - 形象词表 / 工具声明

// 0x0013580
NSArray<NSDictionary *> *PDAIToolDeclarations(void)
{
    // F 0x13580：全函数只有一次 objectForKeyedSubscript:（0x135a0，键 @"tools"），
    // 直接取 root 顶层；manifest JSON 里 "tools" 与 "manifest" 同级，没有中间一跳。
    NSArray *builtin = [PDAIManifestRoot() objectForKeyedSubscript:@"tools"];
    // 自检期望值：builtin.count == 20（kPDAIManifestJSON 顶层 "tools" 的条目数：
    //   pet_say/pet_ask/pet_move_to/pet_set/pet_quiet/pet_act + read/write/edit/append/
    //   delete/move/list/glob/grep_files + alarm_set/list/cancel + save_blob/end_turn）。
    // 取错层级时会变成 nil，arrayByAddingObjectsFromArray: 仍返回 nil，整族声明静默丢失；
    // 需要时打开下面这行核对（0 = 层级错）。
    // NSLog(@"PDAIToolDeclarations builtin=%lu", (unsigned long)builtin.count);
    NSArray *device = PDEnabledDeviceToolDeclarations();
    return [builtin arrayByAddingObjectsFromArray:device];
}

// 0x0013630
NSArray<NSDictionary *> *PDAIVocabulary(void)
{
    static NSArray *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSDictionary *manifest = [PDAIManifestRoot() objectForKeyedSubscript:@"manifest"];
        NSMutableArray *vocab = [[manifest objectForKeyedSubscript:@"vocab"] mutableCopy];
        [vocab addObject:@{@"id": @"play_ball",
                           @"kind": @"motion",
                           @"names": @{@"en": @[@"play ball", @"bounce the ball"],
                                       @"zh": @[@"玩球", @"拍球", @"玩玩具球"]},
                           @"about": @{@"en": @"dribbles vertically three times, then accidentally knocks the fourth bounce sideways; works with every outfit",
                                       @"zh": @"连续垂直拍球三次，第四次不小心拍偏，看球弹走；适用于所有服饰"},
                           @"seconds": @6.6}];   // E 0x533b0: __objc_doubleobj 0x401a666666666666 = 6.6
        cached = [vocab copy];
    });
    return cached;
}

// 0x001370c
NSString *PDAIDefaultEnvironment(void) { return kPDAIEnvironmentText; }

// 0x0013718
NSString *PDAIDefaultPersona(void) { return kPDAIPersonaText; }

// 0x0013724
NSString *PDAIOrientation(void) { return kPDAIOrientationText; }

// 0x0013730
NSDictionary *PDAIWord(NSString *token)
{
    static NSDictionary *index;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *built = [NSMutableDictionary dictionary];
        for (NSDictionary *entry in PDAIVocabulary()) {
            id wid = [entry objectForKeyedSubscript:@"id"];
            [built setObject:entry forKeyedSubscript:wid];
            for (NSArray *names in [[entry objectForKeyedSubscript:@"names"] allValues]) {
                for (NSString *name in names) {
                    [built setObject:entry forKeyedSubscript:name];
                    [built setObject:entry forKeyedSubscript:[name lowercaseString]];
                }
            }
        }
        index = built;
    });
    NSString *trimmed = [PDAIString(token)
                         stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSDictionary *hit = [index objectForKeyedSubscript:[trimmed lowercaseString]];
    if (hit)
        return hit;
    return [index objectForKeyedSubscript:trimmed];
}

// 0x0013ae4
NSDictionary<NSString *, NSArray *> *PDAIParseActions(NSArray *tokens)
{
    NSMutableArray *actions = [NSMutableArray array];
    NSMutableArray *dropped = [NSMutableArray array];
    for (id token in tokens) {
        NSDictionary *word = PDAIWord(token);
        if (word) {
            [actions addObject:[word objectForKeyedSubscript:@"id"]];
        } else {
            NSString *desc = [token description];
            [dropped addObject:(desc ?: @"null")];
        }
    }
    return @{@"actions": actions, @"dropped": dropped};
}

#pragma mark - 台词脚本

// 0x0014344  新段：actions 数组 + 空 text / 空 anchors
static NSMutableDictionary *PDAIScriptSegment(NSArray *actions)
{
    return [@{@"actions": actions,
              @"text": [NSMutableString string],
              @"anchors": [NSMutableArray array]} mutableCopy];
}

// 0x0014438  拆词（,，、空格换行制表）→ 词 id 数组；未识别的词并入 dropped
static NSArray *PDAIScriptActions(NSString *chunk, NSMutableArray *dropped)
{
    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@",，、 \n\r\t"];
    NSArray *pieces = [chunk componentsSeparatedByCharactersInSet:separators];
    NSMutableArray *words = [NSMutableArray array];
    for (NSString *piece in pieces) {
        if (piece.length)
            [words addObject:piece];
    }
    NSDictionary *parsed = PDAIParseActions(words);
    [dropped addObjectsFromArray:[parsed objectForKeyedSubscript:@"dropped"]];
    return [parsed objectForKeyedSubscript:@"actions"];
}

// 0x00145f0  段是否有内容
static BOOL PDAIScriptSegmentHasContent(NSDictionary *segment)
{
    if ([[segment objectForKeyedSubscript:@"actions"] count])
        return YES;
    if ([[segment objectForKeyedSubscript:@"anchors"] count])
        return YES;
    NSString *text = PDAIString([segment objectForKeyedSubscript:@"text"]);
    return [[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] != 0;
}

// 0x0013cac
NSDictionary<NSString *, NSArray *> *PDAIParseScript(NSString *script)
{
    NSString *text = PDAIString(script);
    NSMutableArray *beats = [NSMutableArray array];
    NSMutableArray *dropped = [NSMutableArray array];
    NSMutableDictionary *segment = PDAIScriptSegment(@[]);

    NSUInteger i = 0;
    NSUInteger length = text.length;
    while (i < length) {
        unichar c = [text characterAtIndex:i];
        if (c == '【') {
            // 【词, 词】整组先做，然后换新气泡
            NSRange found = [text rangeOfString:@"】"
                                        options:0
                                          range:NSMakeRange(i + 1, length - i - 1)];
            if (found.location == NSNotFound) {
                [[segment objectForKeyedSubscript:@"text"] appendString:[text substringFromIndex:i]];
                break;
            }
            NSString *inner = [text substringWithRange:NSMakeRange(i + 1, found.location - i - 1)];
            NSArray *actions = PDAIScriptActions(inner, dropped);
            if (PDAIScriptSegmentHasContent(segment))
                [beats addObject:segment];
            segment = PDAIScriptSegment(actions);
            i = found.location;
        } else if (c == '<' || c == 0xff1c) {
            // <词>／＜词＞：打到这段文字时做，不换气泡
            NSString *closer = (c == '<') ? @">" : @"＞";
            NSRange found = [text rangeOfString:closer
                                        options:0
                                          range:NSMakeRange(i + 1, length - i - 1)];
            BOOL isMarker = NO;
            NSString *word = nil;
            if (found.location != NSNotFound) {
                word = [text substringWithRange:NSMakeRange(i + 1, found.location - i - 1)];
                if (word.length <= 0x20 && ![word containsString:@"\n"])
                    isMarker = YES;
            }
            if (isMarker) {
                NSArray *actions = PDAIScriptActions(word, dropped);
                if (actions.count) {
                    NSMutableDictionary *anchor =
                        [@{@"at": @([[segment objectForKeyedSubscript:@"text"] length]),
                           @"actions": actions} mutableCopy];
                    [[segment objectForKeyedSubscript:@"anchors"] addObject:anchor];
                }
                i = found.location;
            } else {
                [[segment objectForKeyedSubscript:@"text"] appendString:[text substringWithRange:NSMakeRange(i, 1)]];
            }
        } else {
            [[segment objectForKeyedSubscript:@"text"] appendString:[text substringWithRange:NSMakeRange(i, 1)]];
        }
        i++;
    }
    if (PDAIScriptSegmentHasContent(segment))
        [beats addObject:segment];

    // 段文本去首尾空白，并把 anchor 的 at 对齐到去空白后的坐标
    for (NSMutableDictionary *beat in beats) {
        NSString *raw = [beat objectForKeyedSubscript:@"text"];
        NSRange firstNonSpace = [raw rangeOfCharacterFromSet:
                                 [[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet]];
        NSUInteger lead = (firstNonSpace.location == NSNotFound) ? raw.length : firstNonSpace.location;
        NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [beat setObject:trimmed forKeyedSubscript:@"text"];
        for (NSMutableDictionary *anchor in [beat objectForKeyedSubscript:@"anchors"]) {
            NSInteger at = [[anchor objectForKeyedSubscript:@"at"] integerValue] - (NSInteger)lead;
            if (at < 0)
                at = 0;
            NSInteger len = (NSInteger)trimmed.length;
            if (at > len)
                at = len;
            [anchor setObject:@(at) forKeyedSubscript:@"at"];
        }
    }
    return @{@"beats": beats, @"dropped": dropped};
}

// 0x00146ec
double PDAIScriptSeconds(NSArray *beats, double rate)
{
    double total = 0;
    double minRate = fmax(rate, 0.5);
    for (NSDictionary *beat in beats) {
        if ([[beat objectForKeyedSubscript:@"actions"] count] == 0)
            total += 0.5;
        NSUInteger len = [[beat objectForKeyedSubscript:@"text"] length];
        if (len) {
            double n = (double)len;
            total += (n / 20.0 + 1.6 + n * 0.07) / minRate;
        }
    }
    return round(total * 10.0) / 10.0;
}

#pragma mark - 自主设置 / 提示词变量

// 0x00148a8
NSArray<NSString *> *PDAISelfKeys(void)
{
    return @[@"figure", @"scheme", @"roam", @"snoreSeconds", @"sound", @"scale",
             @"bubbleSize", @"fontSize", @"theme", @"hoverButtons", @"user"];
}

// 0x00148b4
NSDictionary<NSString *, NSNumber *> *PDAIDirectSettings(void)
{
    NSString *mode = PDAIString(PDAIPreference(@"AISelfAdjust", @"default"));
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSArray *directKeys = @[@"figure", @"scheme", @"roam", @"snoreSeconds"];
    for (NSString *key in PDAISelfKeys()) {
        BOOL allowed = [directKeys containsObject:key];
        if ([mode isEqual:@"any"]) {
            allowed = YES;
        } else if ([mode isEqual:@"off"]) {
            allowed = NO;
        } else if ([mode isEqual:@"custom"]) {
            NSString *prefKey = [@"AISelf_" stringByAppendingString:key];
            allowed = [PDAIPreference(prefKey, @(allowed)) boolValue];
        }
        [out setObject:@(allowed) forKeyedSubscript:key];
    }
    return out;
}

// 0x0014af0
NSDictionary<NSString *, NSString *> *PDAIPromptValues(void)
{
    NSString *user = PDAIString(PDAIPreference(@"AIUserName", @"主人"));
    if (user.length == 0)
        user = @"主人";
    NSString *scheme = PDAIString(PDAIPreference(@"Scheme", @"deepseek"));
    NSString *outfit = PDAIString(PDAIPreference(@"Outfit", @"maid"));
    NSDictionary *manifest = [PDAIManifestRoot() objectForKeyedSubscript:@"manifest"];

    // 词表表格
    NSMutableString *vocabTable = [NSMutableString string];
    for (NSString *kind in @[@"expression", @"motion"]) {
        NSString *header = [kind isEqual:@"motion"] ? @"动作:"
                                                    : @"表情(持续几秒后回到平常的脸):";
        [vocabTable appendFormat:@"%@\n\n| 词 | 中文 | 样子 |\n|---|---|---|\n", header];
        for (NSDictionary *entry in PDAIVocabulary()) {
            if (![[entry objectForKeyedSubscript:@"kind"] isEqual:kind])
                continue;
            NSString *zh = [[[entry objectForKeyedSubscript:@"names"] objectForKeyedSubscript:@"zh"]
                            componentsJoinedByString:@" / "];
            NSString *aboutZh = [[entry objectForKeyedSubscript:@"about"] objectForKeyedSubscript:@"zh"] ?: @"";
            NSString *lasting = [[entry objectForKeyedSubscript:@"lasting"] boolValue] ? @",保持到下一个动作" : @"";
            [vocabTable appendFormat:@"| %@ | %@ | %@%@ |\n",
             [entry objectForKeyedSubscript:@"id"], zh, aboutZh, lasting];
        }
        [vocabTable appendString:@"\n"];
    }

    // 形象轴与当前选择
    NSMutableArray *axesLines = [NSMutableArray array];
    NSMutableArray *chosenLabels = [NSMutableArray array];
    for (NSDictionary *axis in [manifest objectForKeyedSubscript:@"axes"]) {
        NSMutableArray *options = [NSMutableArray array];
        for (NSDictionary *option in [axis objectForKeyedSubscript:@"options"]) {
            NSString *label = [[option objectForKeyedSubscript:@"name"] objectForKeyedSubscript:@"zh"];
            if (!label)
                label = [option objectForKeyedSubscript:@"id"];
            [options addObject:[NSString stringWithFormat:@"%@(%@)",
                                [option objectForKeyedSubscript:@"id"], label]];
            NSString *wanted = [[axis objectForKeyedSubscript:@"id"] isEqual:@"scheme"] ? scheme : outfit;
            if ([[option objectForKeyedSubscript:@"id"] isEqual:wanted])
                [chosenLabels addObject:label];
        }
        [axesLines addObject:[NSString stringWithFormat:@"%@:%@",
                              [axis objectForKeyedSubscript:@"id"],
                              [options componentsJoinedByString:@"、"]]];
    }

    // 自主设置
    NSMutableArray *onKeys = [NSMutableArray array];
    NSMutableArray *offKeys = [NSMutableArray array];
    NSDictionary *direct = PDAIDirectSettings();
    for (NSString *key in PDAISelfKeys()) {
        if ([[direct objectForKeyedSubscript:key] boolValue])
            [onKeys addObject:key];
        else
            [offKeys addObject:key];
    }
    NSString *selfText;
    if ([PDAIPreference(@"AISelfAdjust", @"default") isEqual:@"off"]) {
        selfText = @"自主配置权限为禁止，pet_set 和 pet_quiet 当前不能使用。";
    } else {
        selfText = [NSString stringWithFormat:@"现在直接生效的:%@;先在气泡里征得%@同意的:%@。",
                    [onKeys componentsJoinedByString:@"、"], user,
                    [offKeys componentsJoinedByString:@"、"]];
    }

    NSString *body = [NSString stringWithFormat:@"%@,%@(%@)",
                      [[manifest objectForKeyedSubscript:@"name"] objectForKeyedSubscript:@"zh"],
                      [[manifest objectForKeyedSubscript:@"about"] objectForKeyedSubscript:@"zh"],
                      [chosenLabels componentsJoinedByString:@","]];
    NSString *dress = [NSString stringWithFormat:
                       @"- figure:whale(DeepSeek 大肥鱼)\n- scheme:按 scheme-outfit 顺序用 - 连接。%@",
                       [axesLines componentsJoinedByString:@";"]];

    return @{@"pet.user": user,
             @"pet.vocab": vocabTable,
             @"pet.moves": @"",
             @"pet.voice": @"关着",
             @"pet.body": body,
             @"pet.dress": dress,
             @"pet.self": selfText,
             @"pet.chat": @"近期对话保存在本机，用户可清空。重要且明确的长期偏好、互动习惯写入 KEY_MEMORY.md，通过文件工具更新；它与 CONSTITUTION.md、PARTNER.md 在清理时保留，用户可在 iOS 设置的记忆页面查看与编辑。普通过程笔记可被清理。",
             @"pet.reply": @"",
             @"pet.cua": PDDeviceToolPrompt()};
}

// 0x0015774  偏好名 → 短键
static NSDictionary *PDAIProviderKeyMap(void)
{
    return @{@"AIAcceptImages": @"images", @"AIBaseURL": @"base", @"AIContextTokens": @"context",
             @"AIEndpointPath": @"endpoint", @"AIExtraBody": @"extra", @"AIExtraHeaders": @"headers",
             @"AIKeepPastThinking": @"keepThinking", @"AIMaxTokens": @"maxTokens", @"AIModel": @"model",
             @"AIProtocol": @"protocol", @"AIReasoningEffort": @"effort", @"AIReasoningReplay": @"replay",
             @"AISyntheticReasoning": @"synthetic", @"AISyntheticReasoningText": @"syntheticText",
             @"AITemperature": @"temperature", @"AIThinking": @"thinking"};
}

// 0x0015774  默认值
static NSDictionary *PDAIProviderDefaults(void)
{
    return @{@"AIAcceptImages": @NO, @"AIBaseURL": @"", @"AIContextTokens": @128000,
             @"AIEndpointPath": @"", @"AIExtraBody": @"", @"AIExtraHeaders": @"",
             @"AIKeepPastThinking": @YES, @"AIMaxTokens": @0, @"AIModel": @"",
             @"AIProtocol": @"chat", @"AIReasoningEffort": @"auto", @"AIReasoningReplay": @"encrypted",
             @"AISyntheticReasoning": @YES, @"AISyntheticReasoningText": @"-",
             @"AITemperature": @(-1), @"AIThinking": @"auto"};
}

NSDictionary<NSString *, id> *PDAIProviderSettings(void)
{
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSDictionary *keys = PDAIProviderKeyMap();
    NSDictionary *defaults = PDAIProviderDefaults();
    for (NSString *name in keys) {
        id value = PDAIPreference(name, [defaults objectForKeyedSubscript:name]);
        [out setObject:value forKeyedSubscript:[keys objectForKeyedSubscript:name]];
    }
    return out;
}

#pragma mark - 端点

// 0x00158dc
NSURL *PDAIEndpoint(NSDictionary *settings)
{
    NSString *base = PDAIString([settings objectForKeyedSubscript:@"base"]);
    base = [base stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([base hasSuffix:@"/"]) {
        do {
            base = [base substringToIndex:base.length - 1];
        } while ([base hasSuffix:@"/"]);
    }
    for (NSString *suffix in @[@"/chat/completions", @"/responses"]) {
        if ([base hasSuffix:suffix])
            base = [base substringToIndex:base.length - suffix.length];
    }
    NSString *path = PDAIString([settings objectForKeyedSubscript:@"endpoint"]);
    if (path.length == 0) {
        path = [[settings objectForKeyedSubscript:@"protocol"] isEqual:@"responses"]
             ? @"/responses" : @"/chat/completions";
    }
    if (![path hasPrefix:@"/"] || [path hasPrefix:@"//"])
        return nil;
    NSURL *url = [NSURL URLWithString:[base stringByAppendingString:path]];
    if (url.host.length == 0)
        return nil;
    if (![@[@"http", @"https"] containsObject:[[url scheme] lowercaseString]])
        return nil;
    return url;
}

// 0x0015c28
NSUInteger PDAIEstimatedTokens(id obj)
{
    if ([obj isKindOfClass:[NSString class]]) {
        NSString *text = obj;
        NSUInteger length = text.length;
        if (length == 0)
            return 0;
        NSUInteger wide = 0, ascii = 0;
        for (NSUInteger i = 0; i < length; i++) {
            unichar c = [text characterAtIndex:i];
            if (c > 0x7f)
                wide++;
            if (c < 0x80)
                ascii++;
        }
        return (ascii + 2) / 3 + wide * 2;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        NSUInteger total = 0;
        for (id child in obj)
            total = total + PDAIEstimatedTokens(child) + 4;
        return total;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSUInteger total = 0;
        for (id key in obj) {
            if ([key isEqual:@"_attachments"]) {
                total += [[obj objectForKeyedSubscript:key] count] << 13;
                continue;
            }
            if ([key hasPrefix:@"_"])
                continue;
            total = total + PDAIEstimatedTokens(key)
                          + PDAIEstimatedTokens([obj objectForKeyedSubscript:key]) + 4;
        }
        return total;
    }
    return 4;
}

// 0x0015f10
NSString *PDAIImageEndpointKey(NSDictionary *settings)
{
    NSString *absolute = [PDAIEndpoint(settings) absoluteString];
    return [@[absolute ?: @"",
              PDAIString([settings objectForKeyedSubscript:@"protocol"]),
              PDAIString([settings objectForKeyedSubscript:@"model"]),
              PDAIString([settings objectForKeyedSubscript:@"extra"]),
              PDAIString([settings objectForKeyedSubscript:@"headers"])]
            componentsJoinedByString:@"\n"];
}

#pragma mark - 历史与图片

// 0x00160c0
NSArray *PDAIHistoryWithoutImages(NSArray *messages, id keepIDs)
{
    if (messages.count == 0)
        return messages;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:messages.count];
    for (NSDictionary *message in messages) {
        NSMutableArray *kept = [NSMutableArray array];
        NSMutableArray *droppedIDs = [NSMutableArray array];
        for (id att in [message objectForKeyedSubscript:@"_attachments"]) {
            if (PDAIAttachmentIsImage(att)) {
                if ([keepIDs containsObject:PDAIString([att objectForKeyedSubscript:@"id"])])
                    [droppedIDs addObject:[att objectForKeyedSubscript:@"id"]];
                else
                    [kept addObject:att];
            } else {
                [kept addObject:att];
            }
        }
        if (droppedIDs.count == 0) {
            [out addObject:message];
            continue;
        }
        NSMutableDictionary *copy = [message mutableCopy];
        if (kept.count)
            [copy setObject:kept forKeyedSubscript:@"_attachments"];
        else
            [copy removeObjectForKey:@"_attachments"];
        NSMutableString *content = [PDAIString([message objectForKeyedSubscript:@"content"]) mutableCopy];
        for (id aid in droppedIDs)
            [content appendFormat:@"\n[image_not_delivered log:%@] 模型服务拒收了带图片的请求；此图片未送达。不能声称看过图片，也不能依据这张截图推断界面或点击坐标。", aid];
        [copy setObject:content forKeyedSubscript:@"content"];
        [out addObject:copy];
    }
    return out;
}

// 0x0016554
BOOL PDAIRequestHasImages(id payload)
{
    NSMutableSet *refs = [NSMutableSet set];
    PDAICollectImageRefs(payload, refs);
    return refs.count != 0;
}

// 0x0016888
NSSet<NSString *> *PDAISentImageIDs(id payload, NSArray *history, NSString *root)
{
    NSMutableSet *refs = [NSMutableSet set];
    NSMutableSet *ids = [NSMutableSet set];
    PDAICollectImageRefs(payload, refs);
    if (refs.count) {
        for (NSDictionary *message in PDAIContextSinceLastDelivery(history)) {
            for (NSDictionary *att in [message objectForKeyedSubscript:@"_attachments"]) {
                NSString *aid = PDAIString([att objectForKeyedSubscript:@"id"]);
                NSString *mime = PDAIString([att objectForKeyedSubscript:@"mime"]);
                NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:aid];
                if (!uuid)
                    continue;
                if (!PDAIAttachmentIsImage(att))
                    continue;
                NSString *path = [[root stringByAppendingPathComponent:@"attachments"]
                                  stringByAppendingPathComponent:aid];
                NSData *data = [NSData dataWithContentsOfFile:path];
                if (data.length == 0)
                    continue;
                NSString *uri = [NSString stringWithFormat:@"data:%@;base64,%@",
                                 mime, [data base64EncodedStringWithOptions:0]];
                if ([refs containsObject:uri])
                    [ids addObject:aid];
            }
        }
    }
    return ids;
}

// 0x0016c14
NSArray *PDAIContextSinceLastDelivery(NSArray *messages)
{
    NSUInteger count = messages.count;
    NSInteger handoff = -1;
    for (NSInteger i = (NSInteger)count - 1; i >= 0; i--) {
        NSDictionary *message = messages[i];
        if (![[message objectForKeyedSubscript:@"role"] isEqual:@"user"])
            continue;
        if ([[message objectForKeyedSubscript:@"_handoff"] boolValue])
            continue;
        handoff = i;
        break;
    }
    NSInteger start = PDAILastAssistantIndex(messages) + 1;
    if (handoff < start)
        start = handoff;
    if (start < 1)
        return messages;

    NSMutableArray *copy = nil;
    for (NSInteger i = 0; i < start; i++) {
        NSDictionary *message = messages[i];
        id attachments = [message objectForKeyedSubscript:@"_attachments"];
        if (![attachments isKindOfClass:[NSArray class]])
            continue;
        NSMutableArray *kept = [NSMutableArray array];
        for (id att in attachments) {
            if (!PDAIAttachmentIsImage(att))
                [kept addObject:att];
        }
        if (kept.count == attachments.count)
            continue;
        if (!copy)
            copy = [messages mutableCopy];
        NSMutableDictionary *stripped = [message mutableCopy];
        if (kept.count)
            [stripped setObject:kept forKeyedSubscript:@"_attachments"];
        else
            [stripped removeObjectForKey:@"_attachments"];
        [copy setObject:stripped atIndexedSubscript:i];
    }
    return copy ?: messages;
}

// 0x0016f44
BOOL PDAIImageRetryAllowed(NSInteger status, id body, id error)
{
    if (error)
        return NO;
    if (status < 400 || status > 422)
        return NO;
    // 0x40002001：仅 400 与 413 命中
    uint64_t bit = (uint64_t)1 << (uint64_t)(status - 400);
    if ((bit & 0x40002001ULL) == 0)
        return NO;
    NSString *text = body;
    if (!text) {
        text = [[NSString alloc] initWithData:[NSData data] encoding:NSUTF8StringEncoding];
    }
    NSString *lower = [text lowercaseString] ?: @"";
    for (NSString *keyword in @[@"context_length", @"context length", @"context window",
                                @"context limit", @"context size", @"maximum context",
                                @"context_limit", @"too many tokens", @"token limit",
                                @"maximum number of tokens", @"max_tokens", @"max_input_tokens",
                                @"上下文", @"输入过长"]) {
        if ([lower containsString:keyword])
            return NO;
    }
    return YES;
}

// 0x00171b4
NSInteger PDAIImageSafeHandoffBoundary(NSArray *messages)
{
    NSUInteger count = messages.count;
    NSUInteger imageIndex = count;
    for (NSUInteger i = (NSUInteger)(PDAILastAssistantIndex(messages) + 1); i < count; i++) {
        id attachments = [messages[i] objectForKeyedSubscript:@"_attachments"];
        if (![attachments isKindOfClass:[NSArray class]])
            continue;
        BOOL found = NO;
        for (id att in attachments) {
            if (PDAIAttachmentIsImage(att)) {
                found = YES;
                break;
            }
        }
        if (found) {
            imageIndex = i;
            break;
        }
    }
    NSInteger boundary = NSIntegerMax;
    if (count < 2 || imageIndex == 0)
        return boundary;
    for (NSUInteger i = 1; i < count && i < imageIndex; i++) {
        if (![[messages[i] objectForKeyedSubscript:@"role"] isEqual:@"user"])
            continue;
        if (![[messages[i] objectForKeyedSubscript:@"_handoff"] boolValue])
            boundary = (NSInteger)i;
    }
    return boundary;
}

#pragma mark - 请求体

// 0x0017460
NSMutableDictionary *PDAIRequestBody(NSString *instructions, NSArray *history, NSArray *tools,
                                     NSDictionary *settings, NSString *root, NSError **error)
{
    NSArray *context = PDAIContextSinceLastDelivery(history);
    NSString *protocol = PDAIString([settings objectForKeyedSubscript:@"protocol"]);
    if (![@[@"chat", @"responses"] containsObject:protocol]) {
        if (error)
            *error = PDAIProtocolError(@"未知通信协议。");
        return nil;
    }
    BOOL responses = [protocol isEqual:@"responses"];
    BOOL thinkingOff = [[settings objectForKeyedSubscript:@"thinking"] isEqual:@"off"];
    BOOL keepThinking = PDAIObjectBool([settings objectForKeyedSubscript:@"keepThinking"], YES);
    BOOL acceptImages = PDAIObjectBool([settings objectForKeyedSubscript:@"images"], NO);
    BOOL plaintext = [[settings objectForKeyedSubscript:@"replay"] isEqual:@"plaintext"];
    NSString *origin = PDAIRequestOrigin(settings);
    NSString *effort = PDAIString([settings objectForKeyedSubscript:@"effort"]);
    NSString *model = PDAIString([settings objectForKeyedSubscript:@"model"]);

    NSMutableDictionary *body =
        [@{@"model": model, @"stream": @NO, @"tool_choice": @"auto"} mutableCopy];

    double temperature = PDAINumber([settings objectForKeyedSubscript:@"temperature"], -1);
    if (!(temperature < 0) && !(temperature > 2))
        [body setObject:@(temperature) forKeyedSubscript:@"temperature"];

    NSInteger maxTokens = (NSInteger)PDAINumber([settings objectForKeyedSubscript:@"maxTokens"], 0);
    if (maxTokens >= 1) {
        [body setObject:@(maxTokens)
                 forKeyedSubscript:(responses ? @"max_output_tokens" : @"max_tokens")];
    }

    NSInteger lastUser = -1;
    for (NSUInteger i = 0; i < context.count; i++) {
        if ([[context[i] objectForKeyedSubscript:@"role"] isEqual:@"user"])
            lastUser = (NSInteger)i;
    }

    if (responses) {
        NSMutableArray *input = [NSMutableArray array];
        NSMutableArray *toolArray = [NSMutableArray array];
        for (NSDictionary *tool in tools) {
            NSMutableDictionary *fn = [[tool objectForKeyedSubscript:@"function"] mutableCopy];
            [fn setObject:@"function" forKeyedSubscript:@"type"];
            [toolArray addObject:fn];
        }

        for (NSUInteger i = 0; i < context.count; i++) {
            NSDictionary *message = context[i];
            id role = [message objectForKeyedSubscript:@"role"];
            if ([role isEqual:@"tool"]) {
                id output;
                if (acceptImages &&
                    [[message objectForKeyedSubscript:@"_attachments"] count]) {
                    output = PDAIBuildContent(message, YES, YES, root);
                } else {
                    output = PDAIString([message objectForKeyedSubscript:@"content"]);
                }
                [input addObject:@{@"type": @"function_call_output",
                                   @"call_id": [message objectForKeyedSubscript:@"tool_call_id"],
                                   @"output": output}];
                continue;
            }

            // 旧轮次的推理重放（encrypted_content）
            BOOL reasoningPresent = NO;   // B 0x17e9c w28：本条消息是否已有 reasoning 条目
            // C 0x17a48–0x17a6c：`csel w8, wzr, plaintext, le` + `orr w8, keepThinking, w8`，
            // 即 !thinkingOff && (keepThinking || (i > lastUser && plaintext))。
            BOOL keepThisReasoning = (!thinkingOff &&
                                      (keepThinking || ((NSInteger)i > lastUser && plaintext)));
            if (keepThisReasoning &&
                [[message objectForKeyedSubscript:@"_reasoning"] isKindOfClass:[NSArray class]]) {
                for (NSDictionary *item in [message objectForKeyedSubscript:@"_reasoning"]) {
                    NSMutableDictionary *copy = [item mutableCopy];
                    NSMutableString *texts = [NSMutableString string];
                    for (NSString *key in @[@"content", @"summary"]) {
                        id arr = [copy objectForKeyedSubscript:key];
                        if (![arr isKindOfClass:[NSArray class]])
                            continue;
                        for (id piece in arr) {
                            if ([piece isKindOfClass:[NSDictionary class]])
                                [texts appendString:PDAIString([piece objectForKeyedSubscript:@"text"])];
                        }
                    }
                    BOOL usable = NO;
                    if (plaintext && texts.length) {
                        [copy setObject:@[@{@"type": @"reasoning_text", @"text": texts}]
                                 forKeyedSubscript:@"content"];
                        [copy removeObjectForKey:@"encrypted_content"];
                        usable = YES;
                    } else if (PDAIString([copy objectForKeyedSubscript:@"encrypted_content"]).length) {
                        usable = YES;
                    }
                    if (!usable)
                        continue;
                    if (![[copy objectForKeyedSubscript:@"_origin"] isEqual:origin])
                        [copy removeObjectForKey:@"id"];
                    [input addObject:copy];
                    reasoningPresent = YES;   // 0x17e44 [sp,#0x8c]=1 → 0x183d8 w28 = 1
                }
            }

            // 消息体
            // 消息体：content 非空 → 一条 message；content 空但 role=="user" → 也补一条
            BOOL contentEmpty = (PDAIString([message objectForKeyedSubscript:@"content"]).length == 0);
            if (!contentEmpty || [role isEqual:@"user"]) {
                [input addObject:@{@"type": @"message",
                                   @"role": role,
                                   @"content": PDAIBuildContent(message, YES, acceptImages, root)}];
            }

            // function_call 项 + synthetic reasoning 闸门
            // B 0x180c8：闸门是 w28 =「本条消息已有 reasoning（重放过或已补过）」，
            //   不是「本条是否产出 message 部件」——二进制里没有该比较，也没有 countBefore。
            //   仅在 !thinkingOff && plaintext && !reasoningPresent 时才可能补 synthetic。
            id toolCalls = [message objectForKeyedSubscript:@"tool_calls"];
            if ([toolCalls isKindOfClass:[NSArray class]]) {
                for (NSDictionary *call in toolCalls) {
                    if ((thinkingOff || !plaintext) || reasoningPresent) {
                        // 0x180d4 w28 |= [sp,#0xdc]（= plaintext && !thinkingOff）
                        if (plaintext && !thinkingOff)
                            reasoningPresent = YES;
                    } else if ([message objectForKeyedSubscript:@"_origin"]) {
                        reasoningPresent = NO;      // 0x180fc 有 _origin → w28 = 0
                    } else if (PDAIObjectBool([settings objectForKeyedSubscript:@"synthetic"], YES)) {
                        NSString *synth = PDAIString([settings objectForKeyedSubscript:@"syntheticText"]);
                        if (synth.length == 0)
                            synth = @"-";
                        reasoningPresent = YES;     // 0x181f0 先置位，再入列
                        [input addObject:@{@"type": @"reasoning",
                                           @"summary": @[],
                                           @"content": @[@{@"type": @"reasoning_text",
                                                           @"text": synth}]}];
                    } else {
                        reasoningPresent = NO;      // 0x18348 synthetic 关闭 → w28 = 0
                    }
                    NSDictionary *fn = [call objectForKeyedSubscript:@"function"];
                    [input addObject:@{@"type": @"function_call",
                                       @"call_id": [call objectForKeyedSubscript:@"id"],
                                       @"name": [fn objectForKeyedSubscript:@"name"],
                                       @"arguments": [fn objectForKeyedSubscript:@"arguments"]}];
                }
            }
            // D 0x183a4–0x183b8：responses 循环尾只有 i++，没有 _attachments / role:"user" 补块，
            // 故此处不再有任何图片补发逻辑。
        }

        [body setObject:input forKeyedSubscript:@"input"];
        [body setObject:(instructions ?: @"") forKeyedSubscript:@"instructions"];
        [body setObject:toolArray forKeyedSubscript:@"tools"];
        [body setObject:@NO forKeyedSubscript:@"store"];
        if (!thinkingOff && !plaintext)
            [body setObject:@[@"reasoning.encrypted_content"] forKeyedSubscript:@"include"];
        if (thinkingOff) {
            [body setObject:@{@"effort": @"none"} forKeyedSubscript:@"reasoning"];
        } else if (effort.length && ![effort isEqual:@"auto"]) {
            [body setObject:@{@"effort": effort} forKeyedSubscript:@"reasoning"];
        }
    } else {
        NSMutableArray *messages =
            [NSMutableArray arrayWithObject:@{@"role": @"system", @"content": (instructions ?: @"")}];
        NSArray *copiedKeys = @[@"role", @"content", @"tool_call_id", @"tool_calls"];
        BOOL keepPast = !thinkingOff;
        for (NSUInteger i = 0; i < context.count; i++) {
            NSDictionary *message = context[i];
            NSMutableDictionary *item = [NSMutableDictionary dictionary];
            for (NSString *key in copiedKeys) {
                id value = [message objectForKeyedSubscript:key];
                if (value)
                    [item setObject:value forKeyedSubscript:key];
            }
            id role = [message objectForKeyedSubscript:@"role"];
            if (acceptImages && [role isEqual:@"user"] &&
                [[message objectForKeyedSubscript:@"_attachments"] count]) {
                [item setObject:PDAIBuildContent(message, NO, YES, root) forKeyedSubscript:@"content"];
            }
            if (keepPast && ((NSInteger)i > lastUser || keepThinking)) {
                NSString *reasoning = PDAIString([message objectForKeyedSubscript:@"reasoning_content"]);
                if (reasoning.length)
                    [item setObject:[message objectForKeyedSubscript:@"reasoning_content"]
                             forKeyedSubscript:@"reasoning_content"];
            }
            [messages addObject:item];

            // A 0x1869c–0x188b0：只有「本段连续 tool 消息的最后一条」才补发一条 user 图片消息。
            //   0x186b8 要求 role == "tool"；0x1871c 要求 context[i+1] 不是 tool（或 i 已是最后一条）；
            //   start 由 i 回退到该 tool 段起点，收集区间 [start, i]，不是 [start, count-1]。
            if (acceptImages && [role isEqual:@"tool"] &&
                ((i + 1) >= context.count ||
                 ![[context[i + 1] objectForKeyedSubscript:@"role"] isEqual:@"tool"])) {
                NSUInteger start = i;
                while (start >= 1 &&
                       [[context[start - 1] objectForKeyedSubscript:@"role"] isEqual:@"tool"])
                    start--;
                NSMutableArray *images = [NSMutableArray array];
                for (NSUInteger m = start; m <= i; m++) {
                    if ([[context[m] objectForKeyedSubscript:@"_attachments"] count])
                        [images addObjectsFromArray:PDAIBuildContent(context[m], NO, YES, root)];
                }
                if (images.count)
                    [messages addObject:@{@"role": @"user", @"content": images}];
            }
        }
        [body setObject:messages forKeyedSubscript:@"messages"];
        [body setObject:(tools ?: @[]) forKeyedSubscript:@"tools"];
        if (thinkingOff) {
            [body setObject:@"none" forKeyedSubscript:@"reasoning_effort"];
        } else if (effort.length && ![effort isEqual:@"auto"]) {
            [body setObject:effort forKeyedSubscript:@"reasoning_effort"];
        }
    }

    // extra：JSON 字符串合并进 body
    NSString *extra = PDAIString([settings objectForKeyedSubscript:@"extra"]);
    if (extra.length) {
        id parsed = [NSJSONSerialization JSONObjectWithData:[extra dataUsingEncoding:NSUTF8StringEncoding]
                                                    options:0
                                                      error:NULL];
        if ([parsed isKindOfClass:[NSDictionary class]])
            [body addEntriesFromDictionary:parsed];
        else {
            if (error)
                *error = PDAIProtocolError(@"附加请求体必须是 JSON 对象。");
            return nil;
        }
    }

    // 原生传输只走完整响应
    if (PDAIObjectBool([body objectForKeyedSubscript:@"stream"], NO)) {
        if (error)
            *error = PDAIProtocolError(@"当前原生传输使用完整响应，请移除附加请求体中的 stream:true。");
        return nil;
    }
    return body;
}

#pragma mark - 响应归一

// 0x00192a8
id PDAINormalizeResponse(NSDictionary *response, NSDictionary *settings, NSError **error)
{
    if (![response isKindOfClass:[NSDictionary class]]) {
        if (error)
            *error = PDAIProtocolError(@"服务响应不是 JSON 对象。");
        return nil;
    }
    BOOL responses = [[settings objectForKeyedSubscript:@"protocol"] isEqual:@"responses"];

    if (responses) {
        if ([[response objectForKeyedSubscript:@"status"] isEqual:@"completed"]) {
            id output = [response objectForKeyedSubscript:@"output"];
            if (![output isKindOfClass:[NSArray class]]) {
                if (error)
                    *error = PDAIProtocolError(@"Responses 缺少 output 数组。");
                return nil;
            }
            NSMutableString *text = [NSMutableString string];
            NSMutableArray *toolCalls = [NSMutableArray array];
            NSMutableArray *reasoning = [NSMutableArray array];
            for (NSDictionary *item in output) {
                if (![item isKindOfClass:[NSDictionary class]])
                    continue;
                id type = [item objectForKeyedSubscript:@"type"];
                if ([type isEqual:@"function_call"]) {
                    id status = [item objectForKeyedSubscript:@"status"];
                    if (status && ![status isEqual:@"completed"]) {
                        if (error)
                            *error = PDAIProtocolError(@"工具调用被截断，未执行。");
                        return nil;
                    }
                    NSString *callID = PDAIString([item objectForKeyedSubscript:@"call_id"]);
                    NSString *name = PDAIString([item objectForKeyedSubscript:@"name"]);
                    id arguments = [item objectForKeyedSubscript:@"arguments"];
                    if (callID.length == 0 || name.length == 0 ||
                        ![arguments isKindOfClass:[NSString class]]) {
                        if (error)
                            *error = PDAIProtocolError(@"工具调用格式无效。");
                        return nil;
                    }
                    [toolCalls addObject:@{@"id": [item objectForKeyedSubscript:@"call_id"],
                                           @"type": @"function",
                                           @"function": @{@"name": [item objectForKeyedSubscript:@"name"],
                                                          @"arguments": arguments}}];
                } else if ([type isEqual:@"message"]) {
                    id content = [item objectForKeyedSubscript:@"content"];
                    if (![content isKindOfClass:[NSArray class]])
                        continue;
                    for (id piece in content) {
                        if (![piece isKindOfClass:[NSDictionary class]])
                            continue;
                        [text appendString:PDAIString([piece objectForKeyedSubscript:@"text"])];
                    }
                } else if ([type isEqual:@"reasoning"]) {
                    [reasoning addObject:item];
                }
            }
            return @{@"role": @"assistant",
                     @"content": text,
                     @"tool_calls": toolCalls,
                     @"_reasoning": reasoning,
                     @"_origin": PDAIRequestOrigin(settings)};
        }

        // 未完成
        NSString *reason = @"";
        id details = [response objectForKeyedSubscript:@"incomplete_details"];
        if ([details isKindOfClass:[NSDictionary class]])
            reason = PDAIString([details objectForKeyedSubscript:@"reason"]);
        if (error) {
            *error = PDAIProtocolError([NSString stringWithFormat:
                @"Responses 未完成（%@ %@），未执行其中的工具。",
                PDAIString([response objectForKeyedSubscript:@"status"]), reason]);
        }
        return nil;
    }

    // chat
    id choices = [response objectForKeyedSubscript:@"choices"];
    id first = [choices isKindOfClass:[NSArray class]] ? [choices firstObject] : nil;
    if (![first isKindOfClass:[NSDictionary class]] ||
        ![[first objectForKeyedSubscript:@"message"] isKindOfClass:[NSDictionary class]]) {
        if (error)
            *error = PDAIProtocolError(@"接口响应中没有有效的 choices[].message。");
        return nil;
    }
    NSString *finish = PDAIString([first objectForKeyedSubscript:@"finish_reason"]);
    if ([@[@"length", @"content_filter"] containsObject:finish]) {
        if (error) {
            *error = PDAIProtocolError([NSString stringWithFormat:
                @"模型响应未完成（%@），未执行可能被截断的工具。", finish]);
        }
        return nil;
    }
    return [first objectForKeyedSubscript:@"message"];
}

#pragma mark - 交接

// 0x0019c00
NSString *PDAIHandoffNote(NSArray *messages, NSUInteger recentCount, NSUInteger tokenBudget)
{
    // tool_call_id → 回执正文
    NSMutableDictionary *receipts = [NSMutableDictionary dictionary];
    for (NSDictionary *message in messages) {
        if (![[message objectForKeyedSubscript:@"role"] isEqual:@"tool"])
            continue;
        id callID = [message objectForKeyedSubscript:@"tool_call_id"];
        if (!callID)
            continue;
        [receipts setObject:PDAIString([message objectForKeyedSubscript:@"content"])
                     forKeyedSubscript:callID];
    }

    NSMutableArray *entries = [NSMutableArray array];
    if (messages.count) {
        for (NSUInteger i = 0; i < messages.count; i++) {
            NSDictionary *message = messages[i];
            if ([[message objectForKeyedSubscript:@"role"] isEqual:@"user"]) {
                if (![message objectForKeyedSubscript:@"_handoff"]) {
                    NSString *content = PDAIString([message objectForKeyedSubscript:@"content"]);
                    if (content.length) {
                        BOOL recent = ((NSInteger)i >= (NSInteger)recentCount);
                        [entries addObject:@{@"body": [message objectForKeyedSubscript:@"content"],
                                             @"recent": @(recent),
                                             @"speech": @NO}];
                    }
                }
            }
            id toolCalls = [message objectForKeyedSubscript:@"tool_calls"];
            if ([toolCalls isKindOfClass:[NSArray class]]) {
                for (NSDictionary *call in toolCalls) {
                    id fn = [call objectForKeyedSubscript:@"function"];
                    id name = [fn objectForKeyedSubscript:@"name"];
                    if ([name isEqual:@"end_turn"])
                        continue;
                    BOOL speech = [@[@"pet_say", @"pet_ask"] containsObject:name];
                    if ((NSInteger)i < (NSInteger)recentCount && speech)
                        continue;
                    BOOL recent = ((NSInteger)i >= (NSInteger)recentCount);
                    NSString *args = PDAIString([fn objectForKeyedSubscript:@"arguments"]);
                    id receipt = [receipts objectForKeyedSubscript:[call objectForKeyedSubscript:@"id"]];
                    NSString *body = [NSString stringWithFormat:@"调用 %@\n入参:%@\n回执:%@",
                                      name, args, receipt ?: @"(还没回来)"];
                    [entries addObject:@{@"body": body, @"recent": @(recent), @"speech": @(speech)}];
                }
            }
        }
    }

    // 去重（同一正文只留最靠后的一次）
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableArray *unique = [NSMutableArray array];
    for (NSDictionary *entry in [entries reverseObjectEnumerator]) {
        NSString *body = [entry objectForKeyedSubscript:@"body"];
        if ([seen containsObject:body])
            continue;
        [seen addObject:body];
        [unique insertObject:entry atIndex:0];
    }

    NSMutableArray *older = [NSMutableArray array];
    NSMutableArray *recentLines = [NSMutableArray array];
    NSUInteger n = unique.count;
    NSUInteger omitted = 0;
    if (n) {
        NSUInteger used = 0xa0;   // 160
        double quarter = ceil((double)n * 0.25);
        double half = ceil((double)n * 0.5);
        NSInteger offset = -1;
        NSUInteger idx = 0;
        for (; idx < n; idx++, offset--) {
            NSDictionary *entry = unique[n + offset];
            BOOL speech = [[entry objectForKeyedSubscript:@"speech"] boolValue];
            NSUInteger limit;
            if ((double)idx < half)
                limit = 0x100;
            else
                limit = 0x40;
            if ((double)idx < quarter)
                limit = 0x400;
            if (speech)
                limit = 0x400;

            NSString *body = [entry objectForKeyedSubscript:@"body"];
            NSUInteger tokens = PDAIEstimatedTokens(body);
            if (tokens > limit) {
                NSUInteger keep = (NSUInteger)((double)limit * (double)body.length /
                                               fmax((double)tokens, 1.0));
                if (keep > 0 && ([body characterAtIndex:keep - 1] & 0xfc00) == 0xd800)
                    keep--;
                body = [NSString stringWithFormat:@"%@\n…[后面约 %lu token 已折叠]",
                        [body substringToIndex:keep], (unsigned long)(tokens - limit)];
            }
            used += PDAIEstimatedTokens(body) + 4;
            if (used > tokenBudget) {
                omitted = n - idx;
                break;
            }
            if ([[entry objectForKeyedSubscript:@"recent"] boolValue])
                [recentLines insertObject:body atIndex:0];
            else
                [older insertObject:body atIndex:0];
        }
    }

    NSMutableString *out = [NSMutableString string];
    if (older.count) {
        [out appendFormat:@"# 交接笔记 · 更早的一段\n\n这一段已经过去了，只作参考。对外发言类调用已整条省略。\n\n%@\n\n",
         [older componentsJoinedByString:@"\n\n"]];
    }
    NSString *tail = omitted ? [NSString stringWithFormat:@"更早的 %lu 条没有进入这份笔记。",
                                (unsigned long)omitted] : @"";
    [out appendFormat:@"# 交接笔记 · 最近的一段\n\n这一段紧接着现在，保留对外发言的具体入参与实际回执；更早的长回执只留了开头。\n%@\n%@",
     tail, [recentLines componentsJoinedByString:@"\n\n"]];
    return out;
}

// 0x001a648
NSString *PDAIHandoffNotice(NSString *root)
{
    return [NSString stringWithFormat:kPDAIHandoffNoticeFormat, root];
}
