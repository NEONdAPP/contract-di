// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from  "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {INPairPool_V2in} from "../tools/interfaces/IProtocol_in.sol";
import {INHistorian_V2in} from "../tools/interfaces/IProtocol_in.sol";

contract NDCA_V2in is Ownable {
    using SafeERC20 for ERC20;
    using SafeMath for uint256;
    
    struct dcaStruct{
        address userAddress;
        uint256 pairId;
        uint256 srcAmount;
        uint256 tau;
        uint256 nextDcaTime;
        uint256 lastDcaTimeOk;
        uint256 destTokenEarned;
        uint256 exeRequired;//0 = Unlimited
        uint256 exeCompleted;
        uint userError;
        uint averageBuyPrice;//USD (precision 6 dec)
        uint code;
        bool fundsTransfer;
    }

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

    mapping (uint256 => dcaStruct) private NDCAs;
    mapping (bytes32 => uint256) private positionDCAs;
    uint256 private activeDCAs;
    uint256 private totalDCAs;

    address private NRouter;
    address private NPairPool;
    address private NHistorian;
    address private NProxy;

    uint256 private minTauLimit; //days
    uint256 private maxTauLimit; //days
    uint256 private minSrcAmount;
    uint256 private maxActiveDCA;
    uint256 constant private defaultApproval = 150000000000000000000;
    uint256 constant private TAU_MULT = 86400;
    
    bool private networkEnable;
    bool private busyRouter;

    //Events
    event DCASwap(uint256 _pairId, address _userAddress, uint256 _destAmount, uint _status, uint256 _timestamp);
    event GetFunds(uint256 _pairId, address _userAddress, uint256 _srcAmount, uint256 _timestamp);
    event Refund(uint256 _pairId, address _userAddress, uint256 _srcAmount, uint256 _timestamp);
    event CreatedDCA(uint256 _pairId, address _userAddress, uint256 _srcAmount, uint256 _tau, uint256 _nExecution, uint256 _timestamp);
    event ClosedDCA(uint256 _pairId, address _userAddress, uint256 _timestamp);
    event CompletedDCA(uint256 _pairId, address _userAddress, uint256 _timestamp);

    /**
     * @dev Throws if called by any account other than the proxy.
     */
    modifier onlyProxy() {
        require(msg.sender == NProxy, "NEON: Only Proxy is allowed");
        _;
    }
    /*
    * Constructor
    * () will be defined the unit of measure
    * @param _minSrcAmount (ether) minimum amount of token to be invested (without decimals)
    * @param _minTauLimit (day) minimum time to be setted to excute the DCA
    * @param _maxTauLimit (day) minimum time to be setted to excute the DCA
    * @param _maxActiveDCA (n) maximum number of active users into the DCA
    */
    constructor(uint256 _minSrcAmount, uint256 _minTauLimit, uint256 _maxTauLimit, uint256 _maxActiveDCA){
        minSrcAmount = _minSrcAmount;
        minTauLimit = _minTauLimit;
        maxTauLimit = _maxTauLimit;
        maxActiveDCA = _maxActiveDCA;
    }
    /* WRITE METHODS*/
    /*
    * @dev Toggle Network Status
    * @req All component has been defined
    */
    function toggleNetwork() external onlyOwner {
        require(NRouter != address(0), "NEON: Router not defined");
        require(NPairPool != address(0), "NEON: PairPool not defined");
        require(NHistorian != address(0), "NEON: Hystorian not defined");
        require(NProxy != address(0), "NEON: Proxy not defined");
        networkEnable = !networkEnable;
    }
    /*
    * @dev Addresses Settings
    * () will be defined the unit of measure
    * @param _NRouter parameter to be modified, if 0 will be ignored
    * @param _NPairPool parameter to be modified, if 0 will be ignored
    * @param _NHistorian parameter to be modified, if 0 will be ignored
    * @param _NProxy parameter to be modified, if 0 will be ignored
    */
    function addressSettings(address _NRouter, address _NPairPool, address _NHistorian, address _NProxy) external onlyOwner {
        NRouter = _NRouter != address(0) ? _NRouter : NRouter;
        NPairPool = _NPairPool != address(0) ? _NPairPool : NPairPool;
        NHistorian = _NHistorian != address(0) ? _NHistorian : NHistorian;
        NProxy = _NProxy != address(0) ? _NProxy : NProxy;
    }
    /*
    * @dev Frequency Range
    * () will be defined the unit of measure
    * @param _min parameter to be modified, if 0 will be ignored
    * @param _max parameter to be modified, if 0 will be ignored
    */
    function setTauLimit(uint256 _min, uint256 _max) external onlyOwner {
        minTauLimit = _min != 0 ? _min : minTauLimit;
        maxTauLimit = _max != 0 ? _max : minTauLimit;
    }
    /*
    * @dev Define max active DCAs
    * () will be defined the unit of measure
    * @param _value (n) amount
    */
    function setMaxActiveDCA(uint256 _value) external onlyOwner {
        maxActiveDCA = _value;
    }

    /*
    * @proxy Toggle Router Status [Router]
    * () will be defined the unit of measure
    */
    function toggleRouter() external onlyProxy {
        busyRouter = !busyRouter;
    }
    /*
    * @proxy Create DCA
    * !User must approve amount to this SC in order to create it!
    * () will be defined the unit of measure
    * @param _pairId pair where will create a DCA
    * @param _userAddress address that create the DCA
    * @param _srcTokenAmount (wei) amount to be sell every tau with all decimals
    * @param _tau execution frequency
    * @param _exeRequired number of execution required (0 = unlimited)
    * @param _exeNow if true the first execution will be at first router scan (in the day)
    */ 
    function createDCA(uint256 _pairId, address _userAddress, uint256 _srcTokenAmount, uint256 _tau, uint256 _exeRequired, bool _exeNow) onlyProxy external {
        require(networkEnable, "NEON: Network disabled");
        require(!busyRouter, "NEON: Router busy try later");
        require(activeDCAs <= maxActiveDCA, "NEON: Limit active DCAs reached");
        require(_pairId > 0, "NEON: Pair id must be > 0");
        require(_tau >= minTauLimit && _tau <= maxTauLimit, "NEON: Tau out of limits");
        bytes32 uniqueId = _getId(_pairId, _userAddress);
        require(NDCAs[positionDCAs[uniqueId]].userAddress == address(0), "NEON: Already created DCA with this pair");
        dcaStruct storage dca = positionDCAs[uniqueId] == 0 ? NDCAs[totalDCAs + 1] : NDCAs[positionDCAs[uniqueId]];
        (address srcToken, uint256 srcDecimals, , , ) = INPairPool_V2in(NPairPool).pairListed(_pairId);
        require(srcToken != address(0), "NEON: Blacklisted pair, can't create DCA");
        require(_srcTokenAmount >= (minSrcAmount * 10 ** srcDecimals), "NEON: Amount requested too low");
        require(ERC20(srcToken).balanceOf(_userAddress) >= _srcTokenAmount, "NEON: Insufficient balance");
        require(ERC20(srcToken).allowance(_userAddress, address(this)) >= (defaultApproval * 10 ** srcDecimals),"NEON: Insufficient approved token");
        dca.fundsTransfer = false;
        dca.code = 0;
        dca.averageBuyPrice = 0;
        dca.userError = 0;
        dca.exeCompleted = 0;
        dca.exeRequired = _exeRequired;
        dca.destTokenEarned = 0;
        dca.lastDcaTimeOk = 0;
        dca.nextDcaTime = _exeNow == true ? block.timestamp : block.timestamp.add(_tau.mul(TAU_MULT));
        dca.tau = _tau;
        dca.srcAmount = _srcTokenAmount;
        dca.pairId = _pairId;
        dca.userAddress = _userAddress;
        if(positionDCAs[uniqueId] == 0){
            positionDCAs[uniqueId] = totalDCAs + 1;
            totalDCAs += 1;
        }
        activeDCAs += 1;
        emit CreatedDCA(_pairId, _userAddress, _srcTokenAmount, _tau, _exeRequired, block.timestamp);
    }
    /*
    * @proxy Close DCA
    * () will be defined the unit of measure
    * @param _pairId pair where DCA will be closed
    * @param _userAddress owner of the DCA
    */ 
    function closeDCA(uint256 _pairId, address _userAddress) external onlyProxy {
        require(!busyRouter, "NEON: Router busy try later");
        _closeDCA(_pairId, 1,  _userAddress);
        emit ClosedDCA(_pairId, _userAddress, block.timestamp);
    }
    /*
    * @proxy DCA-in Execute (pre-execution) [Router]
    * () will be defined the unit of measure
    * @param _dcaId id to execute the DCA
    * @return bool (true = fund transfered, false = not)
    */ 
    function DCAExecute(uint256 _dcaId) external onlyProxy {
        require(networkEnable, "NEON: Network disabled");
        dcaStruct storage dca = NDCAs[_dcaId];
        require(dca.userAddress != address(0), "NEON: DCA not active");
        (address srcToken, , , , ) = INPairPool_V2in(NPairPool).pairListed(dca.pairId);
        require(srcToken != address(0), "NEON: Blacklisted pair, can't be executed");
        require(block.timestamp >= dca.nextDcaTime, "NEON: Execution not required yet");
        if(!(dca.fundsTransfer) && ERC20(srcToken).balanceOf(dca.userAddress) >= dca.srcAmount && ERC20(srcToken).allowance(dca.userAddress, address(this)) >= dca.srcAmount){
            dca.fundsTransfer = true;
            ERC20(srcToken).safeTransferFrom(dca.userAddress, NRouter, dca.srcAmount);
            emit GetFunds(dca.pairId, dca.userAddress, dca.srcAmount, block.timestamp);
        }
    }
    /*
    * @proxy DCA-in Result (post-execution)
    * () will be defined the unit of measure
    * @param _dcaId id to log result
    * @param _destTokenAmount amount user has recieved
    * @param _code DCA result code
    * @param _unitaryPrice unit purchase
    * @return bool state of execution
    */
    function DCAResult(uint256 _dcaId, uint256 _destTokenAmount, uint _code, uint _unitaryPrice) external onlyProxy{
        require(networkEnable, "NEON: Network disabled");
        dcaStruct storage dca = NDCAs[_dcaId];
        require(dca.userAddress != address(0), "NEON: DCA not active");
        (address srcToken, , , , ) = INPairPool_V2in(NPairPool).pairListed(dca.pairId);
        require(srcToken != address(0), "NEON: Blacklisted pair, can't be executed");
        require(block.timestamp >= dca.nextDcaTime, "NEON: Execution not required yet");
        dca.nextDcaTime = dca.nextDcaTime.add(dca.tau.mul(TAU_MULT));
        dca.code = _code;
        dca.userError = _code == 400 || _code == 401 ? dca.userError + 1 : 0;
        if(_code == 200){
            dca.fundsTransfer = false;
            dca.lastDcaTimeOk = block.timestamp;
            dca.destTokenEarned = dca.destTokenEarned.add(_destTokenAmount);
            dca.exeCompleted += 1;
            dca.averageBuyPrice = dca.averageBuyPrice == 0 ? _unitaryPrice : dca.averageBuyPrice.add(_unitaryPrice).div(2);
            //Automatic Complete DCA
            if((dca.exeCompleted >= dca.exeRequired) && (dca.exeRequired > 0)){
                _closeDCA(dca.pairId, 0, dca.userAddress);
                emit CompletedDCA(dca.pairId, dca.userAddress, block.timestamp);
            }
        }else{
            if(dca.fundsTransfer){//Refund
                dca.fundsTransfer = false;
                ERC20(srcToken).safeTransferFrom(NRouter, dca.userAddress, dca.srcAmount);
                emit Refund(dca.pairId, dca.userAddress, dca.srcAmount, block.timestamp);
            }
            if(dca.userError >= 3){//Automatic Close DCA
                _closeDCA(dca.pairId, 2, dca.userAddress);
                emit ClosedDCA(dca.pairId, dca.userAddress, block.timestamp);
            }
        }
        emit DCASwap(dca.pairId, dca.userAddress, _destTokenAmount, _code, block.timestamp);
    }
    /* INTERNAL METHODS*/
    /*
    * @internal Store Data
    * () will be defined the unit of measure
    * @param _userData data to be stored
    * @param _reason (0 = Completed, 1 = User Close DCA, 2 = Insufficient User Approval or Balance)
    * @param _userAddress address that will be associated to the store
    */
    function _storeData(dcaStruct memory _userData, uint _reason, address _userAddress) internal returns(bool){
        INHistorian_V2in.detailStruct memory data;
        data.pairId = _userData.pairId;
        data.closedDcaTime = _userData.lastDcaTimeOk;
        data.destTokenEarned = _userData.destTokenEarned;
        data.reason = _reason;
        INHistorian_V2in(NHistorian).store(_userAddress, data);
        return true;
    }
    /*
    * @internal close DCA
    * () will be defined the unit of measure
    * @param _pairId pair where DCA will be closed
    * @param _reason (0 = Completed, 1 = User Close DCA, 2 = Insufficient User Approval or Balance)
    * @param _userAddress address that create the DCA
    */
    function _closeDCA(uint256 _pairId, uint reason, address _userAddress) internal {
        require(_pairId > 0, "NEON: Pair id must be > 0");
        bytes32 uniqueId = _getId(_pairId, _userAddress);
        require(NDCAs[positionDCAs[uniqueId]].userAddress != address(0), "NEON: DCA Already closed");
        dcaStruct storage dca = NDCAs[positionDCAs[uniqueId]];
        _storeData(dca, reason, _userAddress);
        dca.userAddress = address(0);
        activeDCAs -= 1;
    }
    /*
    * @internal Calculate Fee
    * () will be defined the unit of measure
    * @param _srcTokenAmount amount
    * @param _srcDecimals number of decimals
    */
    function _calcFee(uint256 _srcTokenAmount, uint256 _srcDecimals) internal pure returns(uint256 feePercent){
        if(_srcTokenAmount <= (500*10**_srcDecimals)){
            feePercent = 100;//100 --> 1.00%
        }
        else if(_srcTokenAmount > (500*10**_srcDecimals) && _srcTokenAmount <= (2500*10**_srcDecimals)){
            feePercent = 85;//85 --> 0.85%
        }
        else if(_srcTokenAmount > (2500*10**_srcDecimals) && _srcTokenAmount <= (10000*10**_srcDecimals)){
            feePercent = 72;//72 --> 0.72%
        }
        else if(_srcTokenAmount > (10000*10**_srcDecimals) && _srcTokenAmount <= (50000*10**_srcDecimals)){
            feePercent = 60;//60 --> 0.60%
        }
        else if(_srcTokenAmount > (50000*10**_srcDecimals)){
            feePercent = 50;//50 --> 0.50%
        }
    }   
    /*
    * @internal Generate Unique ID
    * () will be defined the unit of measure
    * @param _userAddress address that create the DCA
    * @param _pairId pair where will create a DCA
    */
    function _getId(uint256 _pairId, address _userAddress) private pure returns (bytes32){
        return keccak256(abi.encodePacked(_pairId, _userAddress));
    }
    /* VIEW METHODS*/
    /*
    * @proxy Neon DCAs numbers
    * () will be defined the unit of measure
    * @return actives total Active DCAs
    * @return totals total DCAs Created
    */
    function numberDCAs() external onlyProxy view returns(uint256 actives, uint256 totals) {
        actives = activeDCAs;
        totals = totalDCAs;
    }
    /*
    * @proxy Network Status
    * () will be defined the unit of measure
    * @return netActive true if network active
    * @return routerBusy true if router busy
    */
    function neonStatus() external view onlyProxy returns(bool netActive, bool routerBusy) {
        netActive = networkEnable;
        routerBusy = busyRouter;
    }
    /*
    * @proxy Pre-Check for DCA execution [Router]
    * () will be defined the unit of measure
    * @param _dcaId DCA id & DCA active
    * @return execute true when need to be execute
    * @return allowanceOK true when allowance OK
    * @return balanceOK true when balance OK
    */
    function DCAChecks(uint256 _dcaId) external view onlyProxy returns(bool execute, bool allowanceOK, bool balanceOK) {
        dcaStruct storage dca = NDCAs[_dcaId];
        if(block.timestamp >= dca.nextDcaTime && dca.userAddress != address(0)){//return if exe required & DCA active
            (address srcToken, , , , ) = INPairPool_V2in(NPairPool).pairListed(dca.pairId);
            execute = true;
            allowanceOK = ERC20(srcToken).allowance(dca.userAddress, address(this)) >= dca.srcAmount;
            balanceOK = ERC20(srcToken).balanceOf(dca.userAddress) >= dca.srcAmount;
        }
    }
    /*
    * @proxy Info to execute DCA [Router]
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
    function DCAInfo(uint256 _dcaId) external view onlyProxy returns(
        address srcToken,
        uint256 srcDecimals,
        address destToken,
        uint256 destDecimals,
        address reciever,
        uint256 typeAMM,
        uint256 srcTokenAmount
    )
    {
        dcaStruct storage dca = NDCAs[_dcaId];
        (srcToken, srcDecimals, destToken, destDecimals, typeAMM) = INPairPool_V2in(NPairPool).pairListed(dca.pairId);
        reciever = dca.userAddress;
        uint256 feePercent = _calcFee(dca.srcAmount, srcDecimals);
        uint256 feeAmount = dca.srcAmount.div(10000).mul(feePercent);//2 decimals
        srcTokenAmount = dca.srcAmount.sub(feeAmount);
    }
    /*
    * @proxy Details info for the user
    * () will be defined the unit of measure
    * @param _pairId pair where needed information
    * @param _userAddress address owner of those information
    * @return dashboardStruct data structure of user info displayed in the Dapp
    */
    function getDetails(uint256 _pairId, address _userAddress) external view onlyProxy returns(dashboardStruct memory){
        bytes32 uniqueId = _getId(_pairId, _userAddress);
        dcaStruct storage dca = NDCAs[positionDCAs[uniqueId]];
        dashboardStruct memory data;
        if(dca.userAddress != address(0)){
            data.dcaActive = true;
            data.pairId = _pairId;
            data.srcTokenAmount = dca.srcAmount;
            data.tau = dca.tau;
            data.nextDcaTime = dca.nextDcaTime;
            data.lastDcaTimeOk = dca.lastDcaTimeOk;
            data.destTokenEarned = dca.destTokenEarned;
            data.exeRequired = dca.exeRequired;
            data.exeCompleted = dca.exeCompleted;
            data.averageBuyPrice = dca.averageBuyPrice;
            data.code = dca.code;
            data.userError = dca.userError;

            (address srcToken, , , , ) = INPairPool_V2in(NPairPool).pairListed(_pairId);
            data.allowanceOK = ERC20(srcToken).allowance(_userAddress, address(this)) >= dca.srcAmount;
            data.balanceOK = ERC20(srcToken).balanceOf(_userAddress) >= dca.srcAmount;
        }
        return data;
    } 
}