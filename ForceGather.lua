GATHER = {38}

local tMin, tMax = 250, 500 -- Delais aléatoire entre les récolte, choisie entre tMin et tMax

local MAP_COMPLEMENTARY = {}
MAP_COMPLEMENTARY.integereractiveElements = {}
MAP_COMPLEMENTARY.statedElements = {}

local STATED_ELEMENTS = {}
local HARVESTABLE_ELEMENTS = {}
local InteractiveThread = {}

local CellArray = {}
local lastPacketElementId = 0
local reveiveInteractPacket = false
local dispatching = false

local gathering, sortByDist = false, false

local condition = (not dispatching and not reveiveInteractPacket)

function move()
    while true do
        ForceGather()
    end
end

function bank()
    PacketSubManager() -- Laissez cette fonction en tête de fonction bank
    Print("La fonction n'est pas inclue au trajet veuillez l'ajoutez", "BANK", "error")
end

function stopped()
    Print("Arrêt du script")
    PacketSubManager()
end

-- Logic Gather

function ForceGather()
    developer:suspendScriptUntilMultiplePackets({ "StatedElementUpdatedMessage", "InteractiveElementUpdatedMessage"}, 1, false)
    global:delay(0.1)

    if #CellArray == 0 then
        InitCellsArray()
    end

    PacketSubManager("gather", true)

    if condition then
        developer:suspendScriptUntilMultiplePackets({ "StatedElementUpdatedMessage", "InteractiveElementUpdatedMessage"}, 1, false)
        --Dump(MAP_COMPLEMENTARY)
        if #InteractiveThread > 0 and condition then
            Dispatcher()
        end

        if condition then
            --Print("Sort mapcomp")
            SortMapComplementary()
        end

        developer:suspendScriptUntilMultiplePackets({ "StatedElementUpdatedMessage", "InteractiveElementUpdatedMessage"}, 1, false)

        if #HARVESTABLE_ELEMENTS > 0 and condition then
            --Print("sort by dist")

            sortByDist = true

            HARVESTABLE_ELEMENTS = TableFilter(HARVESTABLE_ELEMENTS, function(v)
                return CanGather(v.elementTypeId)
            end)

            for _, v in pairs(HARVESTABLE_ELEMENTS) do
                v.distance = ManhattanDistanceCellId(map:currentCell(), v.cellId)
            end

            table.sort(HARVESTABLE_ELEMENTS, function(a, b)
                return a.distance < b.distance
            end)

            sortByDist = false

            gathering = true

            for _, v in pairs(HARVESTABLE_ELEMENTS) do
                developer:suspendScriptUntilMultiplePackets({ "StatedElementUpdatedMessage", "InteractiveElementUpdatedMessage"}, 1, false)
                if not v.deleted then
                    global:delay(global:random(tMin, tMax))
                    map:door(v.cellId)
                end
            end

            gathering = false

            developer:suspendScriptUntilMultiplePackets({ "StatedElementUpdatedMessage", "InteractiveElementUpdatedMessage"}, 1, false)

            if condition then
                MAP_COMPLEMENTARY = {}
                MAP_COMPLEMENTARY.integereractiveElements = {}
                MAP_COMPLEMENTARY.statedElements = {}
                HARVESTABLE_ELEMENTS = {}
                STATED_ELEMENTS = {}
            end
        end
    end
end

function CanGather(gatherId)
    for _, v in pairs(GATHER) do
        if v == gatherId then
            return true
        end
    end
    return false
end

function SortMapComplementary()
    if MAP_COMPLEMENTARY.integereractiveElements ~= nil and MAP_COMPLEMENTARY.statedElements ~= nil then
        for _, vIntegeractive in ipairs(MAP_COMPLEMENTARY.integereractiveElements) do
            if vIntegeractive.onCurrentMap then
                for _, vStated in pairs(MAP_COMPLEMENTARY.statedElements) do
                    if vIntegeractive.elementId == vStated.elementId then
                        local elem = {}
                        elem.deleted = false
                        elem.cellId = vStated.elementCellId
                        elem.elementTypeId = vIntegeractive.elementTypeId
                        elem.elementId = vIntegeractive.elementId
                        if type(vIntegeractive.enabledSkills) == "boolean" or #vIntegeractive.enabledSkills > 0 then
                            elem.skillInstanceUid = vIntegeractive.enabledSkills[1].skillInstanceUid
                            table.insert(HARVESTABLE_ELEMENTS, elem)
                        end
                    end
                end
            end
        end
    end
end

function Dispatcher()
    --Print("Start Dispatcher")
    dispatching = true
    dispatching = true
    for _, v in pairs(InteractiveThread) do
        v()
    end
    InteractiveThread = {}
    lastPacketElementId = 0
    SortMapComplementary()
    dispatching = false
    --Print("end dispatcher")
end

-- Gestion packet

function PacketSubManager(pType, register)
    local allSub = false

    local packetToSub = {
        ["Gather"] = {
            ["MapComplementaryInformationsDataMessage"] = CB_MapComplementaryInfoDataMessageGather,
            ["StatedElementUpdatedMessage"] = CB_StatedElementUpdatedMessage,
            ["InteractiveElementUpdatedMessage"] = CB_InteractiveElementUpdatedMessage
        }
    }

    -- Gestion params
    if type(pType) == "boolean" then
        register = pType
        allSub = true
    elseif pType == nil then
        allSub = true
    end

    -- Logic 
    for kType, vPacketTbl in pairs(packetToSub) do
        if allSub then
            pType = kType
        end
        if string.lower(kType) == string.lower(pType) then
            for packetName, callBack in pairs(vPacketTbl) do
                if register then -- Abonnement au packet
                    if not developer:isMessageRegistred(packetName) then
                        --Print("Abonnement au packet : "..packetName, "packet")
                        developer:registerMessage(packetName, callBack)
                    end            
                else -- Désabonnement des packet
                    if developer:isMessageRegistred(packetName) then
                        --Print("Désabonnement du packet : "..packetName, "packet")
                        developer:unRegisterMessage(packetName)
                    end            
                end
            end
        end
    end
end

function PacketSender(packetName, fn)
    Print("Envoie du packet "..packetName, "packet")
    local msg = developer:createMessage(packetName)

    if fn ~= nil then
        msg = fn(msg)
    end

    developer:sendMessage(msg)
end

-- CallBack GatherFunc

function CB_MapComplementaryInfoDataMessageGather(packet)
    MAP_COMPLEMENTARY = packet
end

function CB_StatedElementUpdatedMessage(packet)
    packet = packet.statedElement
    table.insert(STATED_ELEMENTS, packet)
end

function CB_InteractiveElementUpdatedMessage(packet)
    --Print("Interac")
    reveiveInteractPacket = true
    packet = packet.integereractiveElement
    if packet.onCurrentMap then
        --Print("Check pop depop")
        if #packet.enabledSkills > 0 then
            --Print("Repop")
            for _, v in pairs(STATED_ELEMENTS) do
                --Print(packet.elementId.."   "..v.elementId)
                if v.elementId == packet.elementId then
                    --Print("Repoped elem")
                    if not gathering and not sortByDist then
                        lastPacketElementId = packet.elementId
                        table.insert(InteractiveThread, function()
                            local elementId = v.elementId
                            local elementTypeId = packet.elementTypeId
                            local elementCellId = v.elementCellId
                            table.insert(MAP_COMPLEMENTARY.statedElements, {
                                elementId = elementId,
                                elementCellId = elementCellId
                            })
                            table.insert(MAP_COMPLEMENTARY.integereractiveElements, {
                                elementId = elementId,
                                elementTypeId = elementTypeId,
                                onCurrentMap = true,
                                enabledSkills = {
                                    { skillInstanceUid = 0 }
                                }
                            })
                        end)
                        --developer:suspendScriptUntil("InteractiveElementUpdatedMessage", 0, false)
                    elseif gathering then
                        local elem = {}
                        elem.deleted = false
                        elem.cellId = v.elementCellId
                        elem.elementId = packet.elementId
                        table.insert(HARVESTABLE_ELEMENTS, elem)
                    end
                    break
                end
            end
        elseif #packet.disabledSkills > 0 then
            --Print('depop')
            for _, v in pairs(HARVESTABLE_ELEMENTS) do
                if v ~= nil and v.elementId == packet.elementId then
                    --Print("deleted")
                    v.deleted = true
                    break
                end
            end
        end
    end
    reveiveInteractPacket = false
end

-- Cell to X Y

function InitCellsArray()
    local startX = 0
    local startY = 0
    local cell = 0
    local axeX = 0
    local axeY = 0

    while (axeX < 20) do
        axeY = 0

        while (axeY < 14) do
            CellArray[cell] = {x = startX + axeY, y = startY + axeY}
            cell = cell + 1
            axeY = axeY + 1
        end

        startX = startX + 1
        axeY = 0

        while (axeY < 14) do
            CellArray[cell] = {x = startX + axeY, y = startY + axeY}
            cell = cell + 1
            axeY = axeY + 1
        end

        startY = startY - 1
        axeX = axeX + 1
    end

    --Print("CellArrayInitialised")
end

function ManhattanDistanceCellId(fromCellId, toCellId)
    local fromCoord = CellIdToCoord(fromCellId)
    local toCoord = CellIdToCoord(toCellId)
    if fromCoord ~= nil and toCoord ~= nil then
        return (math.abs(toCoord.x - fromCoord.x) + math.abs(toCoord.y - fromCoord.y))
    end
    return nil
end

function ManhattanDistanceCoord(fromCoord, toCoord)
    return (math.abs(toCoord.x - fromCoord.x) + math.abs(toCoord.y - fromCoord.y))
end

function CellIdToCoord(cellId)
    if IsCellIdValid(cellId) then
        return CellArray[cellId]
    end

    return nil
end

function CoordToCellId(coord)
    return math.floor((((coord.x - coord.y) * 14) + coord.y) + ((coord.x - coord.y) / 2))
end

function IsCellIdValid(cellId)
    return (cellId >= 0 and cellId < 560)
end

-- Utilitaire

function Print(msg, header, msgType)
    local msg = tostring(msg)
    local prefabStr = ""

    if header ~= nil then
        prefabStr = "["..string.upper(header).."] "..msg
    else
        prefabStr = msg
    end

    if msgType == nil then
        global:printSuccess(prefabStr)
    elseif string.lower(msgType) == "normal" then
        global:printMessage(prefabStr)
    elseif string.lower(msgType) == "error" then
        global:printError("[ERROR]["..header.."] "..msg)
    end
end

function TableFilter(tbl, func)
    local newtbl= {}
    for i, v in pairs(tbl) do
        if func(v) then
            table.insert(newtbl, v)
        end
    end
    return newtbl
end

function Dump(t)
    local function dmp(t, l, k)
        if type (t) == "table" then
            Print(string.format ("% s% s:", string.rep ("", l * 2 ), tostring (k)))
            for k, v in pairs(t) do
                dmp(v, l + 1, k)
            end
        else
            Print(string.format ("% s% s:% s", string.rep ( "", l * 2), tostring (k), tostring (t)))
        end
    end

    dmp(t, 1, "root")
end