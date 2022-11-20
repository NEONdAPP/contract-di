//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface INDCA_V2in {
    /* STRUCT*/
    struct dashboardStruct{
        bool dcaActive;
        uint256 pairId;
        uint256 srcTokenAmount;
        uint256 tau;
        uint256 nextDcaTime;
        uint256 lastDcaTimeOk;
        uint256 destTokenEarned;
        uint256 exeRequired;//0 = Unlimited
        uint256 exeCompleted;
        uint averageBuyPrice;
        uint code;
        uint userError;
        bool allowanceOK;
        bool balanceOK;
    }
    /* WRITE METHODS*/
    function toggleRouter() external;//restricted to Proxy
    function createDCA(uint256 _pairId, address _userAddress, uint256 _srcTokenAmount, uint256 _tau, uint256 _exeRequired, bool _exeNow) external;//restricted to Proxy
    function closeDCA(uint256 _pairId, address _userAddress) external;//restricted to Proxy
    function DCAExecute(uint256 _dcaId) external;//restricted to Proxy
    function DCAResult(uint256 _dcaId, uint256 _destTokenAmount, uint _code, uint _unitaryPrice) external;//restricted to Proxy
    /* VIEW METHODS*/
    function numberDCAs() external view returns(uint256 actives, uint256 totals);//restricted to Proxy
    function neonStatus() external view returns(bool netActive, bool routerBusy);//restricted to Proxy
    function DCAChecks(uint256 _dcaId) external view returns(bool execute, bool allowanceOK, bool balanceOK);//restricted to Proxy
    function DCAInfo(uint256 _dcaId) external view returns(
        address srcToken,
        uint256 srcDecimals,
        address destToken,
        uint256 destDecimals,
        address reciever,
        uint256 typeAMM,
        uint256 srcTokenAmount
    );//restricted to Proxy
    function getDetails(uint256 _pairId, address _userAddress) external view returns(dashboardStruct memory);//restricted to Proxy
}

interface INHistorian_V2in {
    /* STRUCT*/
    struct detailStruct{
        uint256 pairId;
        uint256 closedDcaTime;
        uint256 destTokenEarned;
        uint reason; // (0 = Completed, 1 = User Close DCA, 2 = Insufficient User Approval or Balance)
    }
    /* WRITE METHODS*/
    function store(address _userAddress, detailStruct calldata _struct) external;//restricted to NDCA
    function deleteStore(address _userAddress, uint256 _storeId) external;//restricted to NDCA & Proxy
    /* VIEW METHODS*/
    function getHistoryDataBatch(address _userAddress) external view returns(detailStruct[] memory);//restricted to Proxy
    function getHistoryData(address _userAddress, uint256 _storeId) external view returns(uint256 closedDcaTime, uint256 destTokenEarned, uint reason, bool stored);//restricted to Proxy
}

interface INPairPool_V2in {
    /* VIEW METHODS*/
    function numberListedPairs() external view returns(uint256);
    function pairListed(uint256 _id) external view returns(address srcToken, uint256 srcDecimals, address destToken, uint256  destDecimals, uint typeAMM);
}