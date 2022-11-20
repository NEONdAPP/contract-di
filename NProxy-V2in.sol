// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {INDCA_V2in} from "../tools/interfaces/IProtocol_in.sol";
import {INHistorian_V2in} from "../tools/interfaces/IProtocol_in.sol";
import {INPairPool_V2in} from "../tools/interfaces/IProtocol_in.sol";


contract NProxy_V2in is Ownable {
    struct resultStruct{
        uint256 dcaId;
        uint256 destTokenAmount;
        uint code;
        uint unitaryPrice;
    }
    
    address private NRouter;
    address private NPairPool;
    address private NHistorian;
    address private NDCA;

    /**
     * @dev Throws if called by any account other than the Router.
     */
    modifier onlyRouter() {
        require(msg.sender == NRouter, "NEON: Only Router is allowed");
        _;
    }
    /*
    * Constructor
    * () will be defined the unit of measure
    * @param _NDCA address of the NDCA
    * @param _NHistorian address of the NHistorian
    * @param _NRouter address of the NRouter
    * @param _NPairPool address of the NPairPool
    */
    constructor(address _NDCA, address _NHistorian, address _NRouter, address _NPairPool){
        NDCA = _NDCA;
        NHistorian = _NHistorian;
        NRouter = _NRouter;
        NPairPool = _NPairPool;
    }
    /* WRITE METHODS*/
    /*
    * @dev Define router address
    * () will be defined the unit of measure
    * @param _NRouter parameter to be modified, if 0 will be ignored
    * @param _NPairPool parameter to be modified, if 0 will be ignored
    * @param _NHistorian parameter to be modified, if 0 will be ignored
    * @param _NDCA parameter to be modified, if 0 will be ignored
    */
    function addressSettings(address _NDCA, address _NHistorian, address _NRouter, address _NPairPool) external onlyOwner {
        NDCA = _NDCA != address(0) ? _NDCA : NDCA;
        NHistorian = _NHistorian != address(0) ? _NHistorian : NHistorian;
        NRouter = _NRouter != address(0) ? _NRouter : NRouter;
        NPairPool = _NPairPool != address(0) ? _NPairPool : NPairPool;
    }
    /* UI*/
    /*
    * @user Create DCA
    * () will be defined the unit of measure
    * @param _pairId pair where will create a DCA
    * @param _srcTokenAmount (wei) amount to be sell every tau with all decimals
    * @param _tau execution frequency
    * @param _exeRequired number of execution required (0 = unlimited)
    * @param _exeNow if true the first execution will be at first router scan (in the day)
    */ 
    function createDCA(uint256 _pairId, uint256 _srcTokenAmount, uint256 _tau, uint256 _exeRequired, bool _exeNow) external {
        INDCA_V2in(NDCA).createDCA(_pairId, msg.sender, _srcTokenAmount, _tau, _exeRequired, _exeNow);
    }
    /*
    * @user Close DCA
    * () will be defined the unit of measure
    * @param _pairId pair where DCA will be closed
    */ 
    function closeDCA(uint256 _pairId) external {
        INDCA_V2in(NDCA).closeDCA(_pairId, msg.sender);
    }
    /*
    * @user Delete Stored data
    * @param _storeId data id to be deleted
    */
    function deleteStore(uint256 _storeId) external {
        INHistorian_V2in(NHistorian).deleteStore(msg.sender, _storeId);
    }
    /* ROUTER*/
    /*
    * @router Toggle Router Status
    * () will be defined the unit of measure
    */
    function toggleRouter() external onlyRouter {
        INDCA_V2in(NDCA).toggleRouter();
    }
    /*
    * @router DCA-in Execute (pre-execution)
    * () will be defined the unit of measure
    * @param _dcaIds array of ids to execute the DCA (e.g. [1, 2, ..x])
    * @return array of bool (true = fund transfered, false = not)
    */ 
    function DCAExecuteBatch(uint256[] calldata _dcaIds) external onlyRouter {
        uint256 length = _dcaIds.length;
        for(uint256 i; i < length; i++){
            INDCA_V2in(NDCA).DCAExecute(_dcaIds[i]);
        }
    }
    /*
    * @router DCA-in Result (post-execution)
    * () will be defined the unit of measure
    * @param array of _data for dcas executed (e.g. [[1, 69, 200, 6],[2, 69, 200, 6]])
    */
    function DCAResultBatch(resultStruct[] calldata _data) external onlyRouter {
        uint256 length = _data.length;
        for(uint256 i; i < length; i++){
            INDCA_V2in(NDCA).DCAResult(_data[i].dcaId, _data[i].destTokenAmount, _data[i].code, _data[i].unitaryPrice);
        }
    }
    /* VIEW METHODS*/
    /*
    * @user Check if all related contract are defined
    * () will be defined the unit of measure
    * @return true if all related contract are defined
    */
    function isSettingsCompleted() external view returns(bool){
        return NRouter != address(0) && NPairPool != address(0) && NHistorian != address(0) && NDCA != address(0) ? true : false;
    }
    /*
    * @user Network Status
    * () will be defined the unit of measure
    * @return netActive true if network active
    * @return routerBusy true if router busy
    */
    function neonStatus() external view returns(bool netActive, bool routerBusy){
        return INDCA_V2in(NDCA).neonStatus();
    }
    /*
    * @user Check Pair blacklisted
    * () will be defined the unit of measure
    * @param _pairId id of the pair
    * @return true if blacklisted
    */
    function isBlackListed(uint256 _pairId) external view returns(bool){
        (address srcToken, , , , ) = INPairPool_V2in(NPairPool).pairListed(_pairId);
        return srcToken == address(0);
    }
    /*
    * @user Neon DCAs numbers
    * () will be defined the unit of measure
    * @return actives total Active DCAs
    * @return totals total DCAs Created
    */
    function numberDCAs() external view returns(uint256 actives, uint256 totals){
        return INDCA_V2in(NDCA).numberDCAs();
    }
    /* UI*/
    /*
    * @user Get info of current DCA (for creating)
    * () will be defined the unit of measure
    * @param _pairId id of the pair
    * @return dcaActive true if active
    * @return srcToken address of the selected token DCA
    * @return srcDecimals decimals of selected token DCA
    */
    function getCurrentInfo(uint256 _pairId) external view returns(bool dcaActive, address srcToken, uint256 srcDecimals){
        (srcToken, srcDecimals, , , ) = INPairPool_V2in(NPairPool).pairListed(_pairId);
        INDCA_V2in.dashboardStruct memory tempData = INDCA_V2in(NDCA).getDetails(_pairId, msg.sender);
        dcaActive = tempData.dcaActive;
    }
    /*
    * @user Details info for the user
    * () will be defined the unit of measure
    * @return concat array of dashboardStruct (each DCA detail occupies 13 positions, first parameter "false" = no DCAs found)
    */
    function getDetailsBatch() external view returns(INDCA_V2in.dashboardStruct[] memory){
        uint256 totalPairs = INPairPool_V2in(NPairPool).numberListedPairs();
        INDCA_V2in.dashboardStruct[] memory data = new INDCA_V2in.dashboardStruct[](totalPairs);
        uint256 id;
        for(uint256 i=1; i<=totalPairs; i++){
            INDCA_V2in.dashboardStruct memory tempData = INDCA_V2in(NDCA).getDetails(i, msg.sender);
            if(tempData.dcaActive){
                data[id] = tempData;
                id += 1;
            }
        }
        return data;
    }
    /*
    * @user History info for the user
    * () will be defined the unit of measure
    * @return concat array of detailStruct (each DCA history occupies 4 positions, "empty obj = no DCAs found)
    */
    function getHistoryDataBatch() external view returns(INHistorian_V2in.detailStruct[] memory){
        return INHistorian_V2in(NHistorian).getHistoryDataBatch(msg.sender);
    }
    /* ROUTER*/
    /*
    * @router Pre-Check for DCA execution [Router]
    * () will be defined the unit of measure
    * @param _dcaId DCA id
    * @return execute true when need to be execute & DCA active
    * @return allowanceOK true when allowance OK
    * @return balanceOK true when balance OK
    */
    function DCAChecks(uint256 _dcaId) external view onlyRouter returns(bool execute, bool allowanceOK, bool balanceOK){
        return INDCA_V2in(NDCA).DCAChecks(_dcaId);
    }
    /*
    * @router Info to execute DCA [Router]
    * () will be defined the unit of measure
    * @param _dcaId DCA id
    * @return srcToken address of the token
    * @return srcDecimals number of decimals
    * @return destToken address of the token
    * @return destDecimals number of decimals
    * @return reciever address user for DCA
    * @return typeAMM AMM that will execute the swap
    * @return srcTokenAmount amount to be swapped
    */
    function DCAInfo(uint256 _dcaId) external view onlyRouter returns(
        address srcToken,
        uint256 srcDecimals,
        address destToken,
        uint256 destDecimals,
        address reciever,
        uint256 typeAMM,
        uint256 srcTokenAmount
    ){
        return INDCA_V2in(NDCA).DCAInfo(_dcaId);
    }
}