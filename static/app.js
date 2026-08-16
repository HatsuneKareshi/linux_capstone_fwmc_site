// display elements:
const counterElem = document.getElementById("global-bau-counter")
const fuwawaElem = document.getElementById("fuwawa")
const mococoElem = document.getElementById("mococo")
const stats15MinElem = document.getElementById("stat-15m")
const stats60MinElem = document.getElementById("stat-1h")

const fww_stock = document.getElementById("fuwawa-default")
const fww_bau = document.getElementById("fuwawa-bau")
const mcc_stock = document.getElementById("mococo-default")
const mcc_bau = document.getElementById("mococo-bau")

let PREVIOUS_BAU_COUNT = 0

const fuwawa_audio = [
    new Audio("/static/audio/fuwawa-1.mp3"),
    new Audio("/static/audio/fuwawa-2.mp3"),
    new Audio("/static/audio/fuwawa-3.mp3")
]

const FWW_AUDIO_LEN = fuwawa_audio.length

const mococo_audio = [
    new Audio("/static/audio/mocochan-1.mp3"),
    new Audio("/static/audio/mocochan-2.mp3"),
    new Audio("/static/audio/mocochan-3.mp3")
]

const MCC_AUDIO_LEN = mococo_audio.length

mococoElem.addEventListener("click", () => (handleClick("mococo")))
fuwawaElem.addEventListener("click", () => (handleClick("fuwawa")))

async function startPingLoop() {
    try {
        const response = await fetch('/api/ping');

        if (response.ok) {
            const data = await response.json()
            _handleRequest(data)
        }
    } catch (error) {
        console.warn("Ping failed, retrying in 2s...", error);
    } finally {
        setTimeout(startPingLoop, 2000);
    }
}

async function init() {
    const response = await fetch(`/api/bau-count`);
    const data = await response.json();
    console.log(data)
    _handleRequest(data)
}

async function handleClick(who) {
    try {
        const response = await fetch(`/api/bau-req?which=${who}`);
        const data = await response.json();
        console.log(data)
        _handleRequest(data)

    }
    catch (error) {
        console.error("Failed to register click:", error);
    }
}

function _handleRequest(data) { // takes the jsonified data
    const bau_count = data.bau_cnt;
    const is_mococo = data.is_mococo;
    const tally_15m = data.bau_within_last_15m
    const tally_1h = data.bau_within_last_1h
    if (bau_count !== undefined && tally_15m !== undefined && tally_1h != undefined)
        counterElem.innerText = bau_count;
    stats15MinElem.innerText = tally_15m
    stats60MinElem.innerText = tally_1h

    // purely for animations n sounds
    if (PREVIOUS_BAU_COUNT < bau_count && PREVIOUS_BAU_COUNT > 0) {
        if (is_mococo === true) {
            __triggerAnimation(mcc_stock, mcc_bau)
            __baubau(mococo_audio[Math.floor(Math.random() * MCC_AUDIO_LEN)])
            // alert("MOCOCO, BEAAAAAAAMMMMM")
        }
        else if (is_mococo === false) {
            __triggerAnimation(fww_stock, fww_bau)
            __baubau(fuwawa_audio[Math.floor(Math.random() * FWW_AUDIO_LEN)])
            // alert("its FUWAWA's TURN!!!!!")
        }
    }
    else { // this branch solves the problem of either fuwawa or mococo triggering anim and incomplete sounds upon first launch. on first launch
        // PREVIOUS_BAU_COUNT should be 0
        // nothing
    }
    PREVIOUS_BAU_COUNT = bau_count
}

function __triggerAnimation(defaultImg, bauImg) {
    // Reset keyframe animation state
    defaultImg.classList.remove("play-bau-bau");
    bauImg.classList.remove("play-bau-bau");

    // Force CSS reflow to allow re-triggering rapid clicks
    void defaultImg.offsetWidth;

    // Apply keyframe animation class defined in CSS
    defaultImg.classList.add("play-bau-bau");
    bauImg.classList.add("play-bau-bau");

    setTimeout(() => {
        defaultImg.classList.remove("play-bau-bau");
        bauImg.classList.remove("play-bau-bau");
    }, 1200);
}

function __baubau(audioObj) {
    audioObj.currentTime = 0; // Rewind to start for rapid clicks
    audioObj.play().catch(() => { }); // Prevent unhandled promise rejections
}

// onResume:
init()
startPingLoop()

window.addEventListener("DOMContentLoaded", () => {
    init()
    startPingLoop()
});