// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract NHistorian_V2in is Ownable {

    struct dataStruct{
        mapping (uint256 => detailStruct) userData;
        uint256 storeID;
        uint256 bufferID;
    }

    struct detailStruct{
        uint256 pairId;
        uint256 closedDcaTime;
        uint256 destTokenEarned;
        uint reason; // (0 = Completed, 1 = User Close DCA, 2 = Insufficient User Approval or Balance)
    }

    mapping (address => dataStruct) private database;

    address private NDCA;
    address private NProxy;

    event Stored(address _owner, uint256 _storeId, uint256 _timestamp);
    event DeletedStore(address _owner, uint256 _storeId, uint256 _timestamp);

     /**
     * @dev Throws if called by any account other than the NDCA.
     */
    modifier onlyNDCA() {
        require(msg.sender == NDCA, "NEON: Only NDCA is allowed");
        _;
    }
    /**
     * @dev Throws if called by any account other than the NDCA.
     */
    modifier onlyProxy() {
        require(msg.sender == NProxy, "NEON: Only Proxy is allowed");
        _;
    }
    /**
     * @dev Throws if called by any account other than the NDCA or Proxy.
     */
    modifier onlyNDCAnProxy() {
        require(msg.sender == NDCA || msg.sender == NProxy, "NEON: Only NDCA & Proxy is allowed");
        _;
    }

    /* WRITE METHODS*/
    /*
    * @dev Define Addresses Settings of the contract
    * () will be defined the unit of measure
    * @param _NDCA address of NDCA contract, if 0x00 will not be modify
    * @param _NProxy address of NDCA contract, if 0x00 will not be modify
    */
    function addressSettings(address _NDCA, address _NProxy) external onlyOwner {
        NDCA = _NDCA != address(0) ? _NDCA : NDCA;
        NProxy = _NProxy != address(0) ? _NProxy : NProxy;
    }
    /*
    * @NDCA Store data
    * () will be defined the unit of measure
    * @param _userAddress address that own the DCA
    * @param _struct data to be stored
    */
    function store(address _userAddress, detailStruct calldata _struct) external onlyNDCA {
        require(_userAddress != address(0), "NEON: null address not allowed");
        dataStruct storage data = database[_userAddress];
        uint256 storeID;
        if(data.bufferID == 0){
            storeID = data.storeID;
            data.storeID += 1;
        }else{
            storeID = data.bufferID - 1;
        }
        data.userData[storeID + 1].pairId = _struct.pairId;
        data.userData[storeID + 1].closedDcaTime = _struct.closedDcaTime > 0 ? _struct.closedDcaTime : block.timestamp;//Manage case of DCA closed without exe
        data.userData[storeID + 1].destTokenEarned = _struct.destTokenEarned;
        data.userData[storeID + 1].reason = _struct.reason;
        //buffer
        if(data.storeID >= 200){
            data.bufferID = data.bufferID >= 200 ? 1 : data.bufferID + 1; 
        }
        emit Stored(_userAddress, storeID, block.timestamp);
     }
    /*
    * @NDCA&Proxy Delete Stored data
    * () will be defined the unit of measure
    * @param _userAddress address that own the store
    * @param _storeId data id to be deleted
    */
    function deleteStore(address _userAddress, uint256 _storeId) external onlyNDCAnProxy {
        require(_userAddress != address(0), "NEON: Address not defined");
        dataStruct storage data = database[_userAddress];
        uint256 storeID = data.storeID;
        require(_storeId <= storeID, "NEON: Store ID out of limit");
        for(uint256 i=_storeId; i<=storeID; i++){
            data.userData[i] = data.userData[i + 1];
        }
        data.storeID -= 1;
        if(_storeId == data.bufferID){
            data.bufferID -= 1;
        }
        emit DeletedStore(_userAddress, _storeId, block.timestamp);
     }
    /* VIEW METHODS*/
    /*
    * @user Check ifall related contract are defined
    * () will be defined the unit of measure
    * @return true if all related contract are defined
    */
    function isSettingsCompleted() external view returns(bool){
        return NDCA != address(0) && NProxy != address(0) ? true : false;
    }
    /*
    * @proxy History info for the user (Array Struct) Batch
    * () will be defined the unit of measure
    * @param _userAddress address that own the store
    * @return detailStruct user informations
    */
    function getHistoryDataBatch(address _userAddress) external onlyProxy view returns(detailStruct[] memory){
        dataStruct storage data = database[_userAddress];
        uint256 storeID = data.storeID;
        detailStruct[] memory dataOut = new detailStruct[](storeID);
        for(uint256 i=1; i<=storeID; i++){
            dataOut[i-1] = data.userData[i];
        }
        return dataOut;
    }
    /*
    * @proxy History info for the user
    * () will be defined the unit of measure
    * @param _userAddress address that own the store
    * @param _storeId data id to get info
    * @return closedDcaTime DCA closed time
    * @return destTokenEarned DCA total token earned
    * @return stored confirmation data correctly stored
    */
    function getHistoryData(address _userAddress, uint256 _storeId) external onlyProxy view returns(uint256 pairId, uint256 closedDcaTime, uint256 destTokenEarned, uint reason){
        dataStruct storage data = database[_userAddress];
        pairId = data.userData[_storeId].pairId;
        closedDcaTime = data.userData[_storeId].closedDcaTime;
        destTokenEarned = data.userData[_storeId].destTokenEarned;
        reason = data.userData[_storeId].reason;
    }
}