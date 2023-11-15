// SPDX-License-Identifier: None

pragma solidity 0.8.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

// Base contract designed to store all associated data (contracts/RaffleStorage.sol)

contract RaffleStorage is ReentrancyGuard, Ownable {
    bytes4 internal immutable getApprovedSelector = bytes4(keccak256(bytes("getApprovedSelector(uint256)")));
    bytes4 internal immutable isApprovedForAllSelector = bytes4(keccak256(bytes("isApprovedForAll(address,address)")));

    bytes4 internal immutable playerToBalanceSelector = bytes4(keccak256(bytes("playerToBalance()")));
    bytes4 internal immutable nameSelector = bytes4(keccak256(bytes("name()")));
    bytes4 internal immutable symbolSelector = bytes4(keccak256(bytes("symbol()")));
    bytes4 internal immutable uriSelector = bytes4(keccak256(bytes("uri(uint256)")));
    bytes4 internal immutable ownerOfSelector = bytes4(keccak256(bytes("ownerOf(uint256)")));

    bytes4 private immutable minorPrizeTokenStateSelector = bytes4(keccak256(bytes("minorPrizeTokenState()")));
    bytes4 private immutable grandPrizeTokenStateSelector = bytes4(keccak256(bytes("grandPrizeTokenState()")));

    bool internal __creating_raffle__;

    enum RAFFLE_STATE {
        OPEN,
        RAFFLED,
        CANCELED
    }

    struct Raffle {
        RAFFLE_STATE state;
        address raffleOwner;
        address paytoken;
        bool _fixed;
        uint256 s_requestId;
        uint256 treasury;
        uint256 fixedTreasury;
        uint256 nextTokenID;
        uint64 entryFee;
        uint32 startTime;
        uint32 endTimestamp;
        uint32 grandPrizeMargin;
        uint32 minorPrizeMargin;
        uint32 numGrandWins;
        uint32 numBonusWins;
        uint32 operatorMargin;
    }

    mapping(address => Raffle) internal RaffleSettings;
    mapping(address => bool) internal _isRaffle;

    mapping(address => mapping(bytes4 => mapping(uint256 => uint256))) private _storage;
    mapping(address => mapping(bytes4 => mapping(uint256 => string))) private _stringStorage;

    event RaffleCreated(
        address indexed raffleAddress,
        address paytoken, 
        bool _fixed,
        uint64 entryFee,
        uint32 grandPrizeMargin, 
        uint32 minorPrizeMargin,
        uint32 endTimestamp,
        uint32 numGrandWins,
        uint32 numBonusWins
    );
    event RaffleCanceled(address indexed raffleAddress, uint256 amount);
    event OwnerCharged(address indexed raffleAddress, address indexed owner, uint256 amount);
    event PlayerJoined(address indexed raffleAddress, address indexed player, uint256 numOfTokens, uint256 msgValue);
    event PrizeRaffled(address indexed raffleAddress, uint256[] grandPrizeTokens, uint256[] minorPrizeTokens);
    event PrizeWithdrawed(address indexed raffleAddress, address indexed player, uint256 amount);
    event EmergencyWithdrawed(address indexed raffleAddress, address indexed player, uint256 amount);
    event OwnerWithdrawed(address indexed raffleAddress, address indexed owner, uint256 amout);
    event OperatorWithdrawed(address indexed raffleAddress, uint256 amount);

    error UnableDetermineTokenOwner();
    error RequestedTokenNotExist();
    error NotAuthorizedRequest();
    error WrongRaffleState();
    error WrongPaymentSettings();
    error RaffleTimerNotEnded();

    modifier isState(address raffle, RAFFLE_STATE state) {
        _checkState(raffle, state);
        _;
    }

    modifier onlyRaffle() {
        _checkRaffleApproved();
        _;
    }

    modifier onlyRaffleCreator() {
        _checkOwner();
        __creating_raffle__ = true;
        _;
        __creating_raffle__ = false;
    }

    /**
     * @dev Internal function to write to storage
     */
    function write(address raffle, bytes4 selector, uint256 key, uint256 value) internal {
        _storage[raffle][selector][key] = value;
    }

    /**
     * @dev Internal function to to set minor prize token for specific raffle
     */
    function setTokenMinorPrizeState(address raffle, uint256 tokenID, uint256 state) internal {
        write(raffle, minorPrizeTokenStateSelector, tokenID, state);
    }

    /**
     * @dev Internal function to set grand prize token for specific raffle
     */
    function setTokenGrandPrizeState(address raffle, uint256 tokenID, uint256 state) internal {
        write(raffle, grandPrizeTokenStateSelector, tokenID, state);
    }

    /**
     * @dev Internal function to write string value to storage
     */
    function writeString(
        address collection,
        bytes4 selector,
        uint256 key,
        string calldata value
    )
        internal
    {
        _stringStorage[collection][selector][key] = value;
    }

    /**
     * @dev Internal function to set players balance for specific raffle
     */
    function setBalance(address raffle, address account, uint256 amount) internal {
        write(raffle, playerToBalanceSelector, uint160(account), amount);
    }

    /**
     * @dev Returns whether `tokenID` exists.
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     * Tokens starts existing when they are minted (`_mint`)
     */
    function _exists(address raffle, uint256 tokenID) internal view returns (bool) {
        return tokenID < RaffleSettings[raffle].nextTokenID;
    }

    /**
     * @dev Internal function to check if specific raffle is authenticated to interact with factory
     */
    function isRaffle(address raffle) internal view returns (bool) {
        return _isRaffle[raffle];
    }

    /**
     * @dev Internal function to read from storage
     */
    function read(address raffle, bytes4 selector, uint256 key) internal view returns (uint256) {
        return _storage[raffle][selector][key];
    }

    /**
     * @dev Internal function to read string value from storage
     */
    function readString(address collection, bytes4 selector, uint256 key) internal view
        returns (string memory) {
            return _stringStorage[collection][selector][key];
    }

    /**
     * @dev Internal function to check if specific token is minor prize
     */
    function checkTokenMinorPrize(address raffle, uint256 tokenID) internal view returns (bool) {
        return read(raffle, minorPrizeTokenStateSelector, tokenID) > 0;
    }

    /**
     * @dev Internal function to check if specific token is grand prize
     */
    function checkTokenGrandPrize(address raffle, uint256 tokenID) internal view returns (bool) {
        return read(raffle, grandPrizeTokenStateSelector, tokenID) > 0;
    }

    function _checkRaffleApproved() internal view virtual {
        if(!__creating_raffle__ && !isRaffle(_msgSender())) revert NotAuthorizedRequest();
    }

    function _checkState(address raffle, RAFFLE_STATE state) internal view virtual {
        if(RaffleSettings[raffle].state != state) revert WrongRaffleState();
    }

    /**
     * @dev Internal function to calculate margin, using defined at Raffle creation variables
     * Returned value used to calculate amount for withdraw functions
     */
    function calcMargin(uint256 startAmount, uint256 percentage) internal pure returns(uint256) {
        unchecked { return startAmount / 100 * percentage; }
    }
}

interface IVRFAdministrator {
    function requestRandomWords(
        address raffle,
        uint32 _numWords
    ) external returns(uint256 _requestId);

    function transferOwnership(
        address newOwner
    ) external;

    function getRandomWordByRequestId(
        uint256 requestId
    ) external returns (uint256[] memory);
}

// Custom contract for Chainlink's verified randomness consumer control

contract VRFAdministrator is IVRFAdministrator, VRFConsumerBaseV2, Ownable {
    IRaffleFactory private _factory;
    VRFCoordinatorV2Interface private COORDINATOR;

    bytes32 private keyHash = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c; // SEPOLIA Testnet 30 gwei

    uint64 private s_subscriptionId;
    uint32 private callbackGasLimit = 500000;
    uint16 private constant REQUEST_CONFIRMATIONS = 7;

    mapping (uint256 => uint256[]) private s_requestIdToRandomWords;
    mapping (uint256 => address) private requestIdToRaffleAddress;

    event RandomWordsFulfilled(uint256 requestId, uint256[] randomWords);

    error NotAuthorizedRequest();

    constructor(uint64 subscriptionId, address coordinator, address factoryAddress)
    VRFConsumerBaseV2(coordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(coordinator);
        s_subscriptionId = subscriptionId;
        _factory = IRaffleFactory(factoryAddress);
    }

    /**
     * @dev Function to change vrfCoordinator address in case Chainlink will provide related changes
     */
    function changeVRFCoordinator(address newVrfCoordinator) external onlyOwner {
        COORDINATOR = VRFCoordinatorV2Interface(newVrfCoordinator);
    }

    /**
     * @dev Function to change keyHash address to adjust maximum gas price for fulfillRandomWords() request
     */
    function changeVRFHash(bytes32 newKeyHash) external onlyOwner {
        keyHash = newKeyHash;
    }

    /**
     * @dev Function to change subscription id value for funding Chainlink random words requests
     */
    function changeSubscription(uint64 newSubscriptionId) external onlyOwner {
        s_subscriptionId = newSubscriptionId;
    }

    /**
     * @dev Function to change callback gas limit to use for the callback request from coordinator contract
     */
    function changeCallbackGasLimit(uint32 newGasLimit) external onlyOwner {
        callbackGasLimit = newGasLimit;
    }

    function setNewFactory(address newFactory) external onlyOwner {
        _factory = IRaffleFactory(newFactory);
    }

    function getRandomWordByRequestId(uint256 requestId) external view returns (uint256[] memory) {
        return s_requestIdToRandomWords[requestId];
    }

    /**
     * @dev Function to request randomness for specific raffle
     * Can be only accessed via authorized factory contract
     */
    function requestRandomWords(
        address raffle,
        uint32 _numWords
    ) external returns(uint256 _requestId) {
        if (_msgSender() != address(_factory)) revert NotAuthorizedRequest();

        // Will revert if subscription is not set and funded.
        _requestId = COORDINATOR.requestRandomWords(
        keyHash,
        s_subscriptionId,
        REQUEST_CONFIRMATIONS,
        callbackGasLimit,
        _numWords
        );
        requestIdToRaffleAddress[_requestId] = raffle;
    }

    function transferOwnership(
        address newOwner
    )
        public
        virtual
        override(Ownable, IVRFAdministrator)
    {
        super.transferOwnership(newOwner);
    }

    /**
     * @dev Callback function to get randomness from Chainlink verified oracle.
     * Runs internal function to calculate winners.
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        s_requestIdToRandomWords[requestId] = randomWords;
        address raffleAddress = requestIdToRaffleAddress[requestId];
        _factory.getWinners(raffleAddress);

        emit RandomWordsFulfilled(requestId, randomWords);
    }
}

interface IRaffleFactory {
    function setNameSymbol(
        string calldata newName,
        string calldata newSymbol
    ) external;

    function setTokenUri(
        string calldata newUri,
        uint256 tokenID
    ) external;

    function transferFrom(
        address operator,
        address from,
        address to,
        uint256 id
    ) external;

    function setApproved(
        address msgSender,
        address operator,
        uint256 id
    ) external;

    function setApprovalForAll(address msgSender, address operator, bool approved) external;

    function getApproved(uint256 id) external view returns (address);

    function ownerChargeTreasury(
        address raffle,
        address _token,
        uint256 _value,
        address msgSender
    ) external;

    function startRaffle(
        address raffle
    ) external;

    function publicMint(
        address raffle,
        address _token,
        uint256 _value,
        address msgSender,
        uint256 numOfTokens
    ) external returns (uint256 tokenId);

    function getWinners(address raffle) external;

    function withdrawPrize(
        address raffle,
        address msgSender,
        uint256[] calldata tokenIDs
    ) external;

    function ownerWithdraw(
        address raffle,
        address msgSender
    ) external;

    function operatorWithdraw(
        address raffle,
        address msgSender
    ) external;

    function emergencyRaffleCancel(
        address raffle
    ) external;

    function emergencyWithdraw(
        address raffle,
        address from,
        uint256 numOfTokens
    ) external;

    function balanceOf(address raffle, address account) external view returns (uint256);

    function ownerOf(address raffle, uint256 id) external view returns (address);

    function name(address raffle) external view returns (string memory);

    function symbol(address raffle) external view returns (string memory);

    function uri(address raffle, uint256 id) external view returns (string memory);

    function isApprovedForAll(address owner, address operator) external view returns (bool);

    function totalSupply(address raffle) external view returns (uint256);
}

abstract contract RaffleController_721 is RaffleStorage, IRaffleFactory {
    error CannotTransferToZero();
    error UnauthorizedTransfer();
    error UnauthorizedApproval();

    function setNameSymbol(
        string calldata newName,
        string calldata newSymbol
    )
        external
        onlyRaffle()
    {
        writeString(msg.sender, nameSelector, 0, newName);
        writeString(msg.sender, symbolSelector, 0, newSymbol);
    }

    function setTokenUri(
        string calldata newUri,
        uint256 tokenID
    )
        external
        onlyRaffle()
    {
        if(tokenID != type(uint256).max) revert NotAuthorizedRequest();
        writeString(msg.sender, uriSelector, 0, newUri);
    }

    function transferFrom(
        address operator,
        address from,
        address to,
        uint256 tokenID
    )
        external
        onlyRaffle()
    {
        if(to == address(0)) revert CannotTransferToZero();
        if(from != operator) {
            if (getApproved(tokenID) != operator) {
                if (!isApprovedForAll(from, operator)) {
                    if(!isRaffle(operator)) revert UnauthorizedTransfer();
                }
            }
        }
        if(from != ownerOf(msg.sender, tokenID)) revert UnauthorizedTransfer();

        // Clear approvals from the previous owner
        write(msg.sender, getApprovedSelector, tokenID, 0);

        // Update new balance values for 'from' and 'to' addresses
        write(msg.sender, playerToBalanceSelector, uint160(from), balanceOf(msg.sender, from) - 1);
        write(msg.sender, playerToBalanceSelector, uint160(to), balanceOf(msg.sender, to) + 1);

        //Set new owner for token id
        write(msg.sender, ownerOfSelector, tokenID, uint160(to));

        //In case next token id exists but ownership not initialized
        uint256 nextTokenID = tokenID + 1;
        if (read(msg.sender, ownerOfSelector, nextTokenID) == 0) {
            if (_exists(msg.sender, nextTokenID)) {
                write(msg.sender, ownerOfSelector, nextTokenID, uint160(from));
            }
        }
    }

    function setApproved(
        address msgSender,
        address operator,
        uint256 tokenID
    )
        external
        onlyRaffle()
    {
        address owner = ownerOf(msg.sender, tokenID);
        if(msgSender != owner) {
            if (!isApprovedForAll(owner, msgSender)) {
                revert UnauthorizedApproval();
            }
        }
        write(msg.sender, getApprovedSelector, tokenID, uint160(operator));
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(
        address msgSender,
        address operator,
        bool approved
    )
        external
        onlyRaffle()
    {
        write(
            msg.sender,
            isApprovedForAllSelector,
            uint256(keccak256(abi.encodePacked(msgSender, operator))),
            approved?1:0
        );
    }

    function uri(address raffle, uint256 tokenID) external view onlyRaffle() returns (string memory _uri) {
        if (_exists(raffle, tokenID)) {
            _uri = string(
                abi.encodePacked(readString(raffle, uriSelector, 0), Strings.toString(tokenID), ".json")
            );
        }
    }

    function name(address raffle) external onlyRaffle() view returns (string memory) {
            return readString(raffle, nameSelector, 0);
    }

    function symbol(address raffle) external onlyRaffle() view returns (string memory) {
            return readString(raffle, symbolSelector, 0);
    }

    function ownerOf(address raffle, uint256 tokenID) public view returns (address) {
            if (!_exists(raffle, tokenID)) revert RequestedTokenNotExist();
            unchecked {
            for (uint curr = tokenID; curr >= 0; --curr) {
                address owner = address(uint160(read(raffle, ownerOfSelector, curr)));
                if (owner != address(0)) {
                    return owner;
                }
            }
            revert UnableDetermineTokenOwner();
        }
    }

    function balanceOf(address raffle, address account) public view onlyRaffle() returns (uint256) {
        return read(raffle, playerToBalanceSelector, uint160(account));
    }

    function getApproved(uint256 tokenID) public view onlyRaffle()
        returns (address) {
            return address(uint160(read(msg.sender, getApprovedSelector, tokenID)));
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator)
        public
        view
        onlyRaffle()
        returns (bool)
    {
        return read(
            msg.sender,
            isApprovedForAllSelector,
            uint256(keccak256(abi.encodePacked(owner, operator)))
        ) > 0;
    }

    /**
     * @dev See {IERC721Enumerable-totalSupply}.
     */
    function totalSupply(address raffle) public view onlyRaffle() returns (uint256) {
        return RaffleSettings[raffle].nextTokenID - 1;
    }

    function mintTo(
        address raffle,
        address to,
        uint256 tokenID,
        uint256 numOfTokens
    )
        internal
    {
        write(raffle, ownerOfSelector, tokenID, uint160(to));
        RaffleSettings[raffle].nextTokenID = tokenID + numOfTokens;

        setBalance(raffle, to, balanceOf(raffle, to) + numOfTokens);
    }
}

interface IRaffleSettings {
    struct StartSettings {
        address raffleOwner;
        address paytoken;
        bool _fixed;
        uint64 entryFee;
        uint32 endTimestamp;
        uint32 grandPrizeMargin;
        uint32 minorPrizeMargin;
        uint32 numGrandWins;
        uint32 numBonusWins;
        uint32 operatorMargin;
    }
}

// Factory style core contract to deploy and control different raffles

contract RaffleFactory is RaffleController_721, IRaffleSettings {
    IVRFAdministrator private _vrf;

    event VRFAdministratorCreated(address vrfAddress);

    constructor() {
        _vrf = new VRFAdministrator(
            1058,
            0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625, // SEPOLIA Testnet VRF Coordinator
            address(this)
        );
        _vrf.transferOwnership(_msgSender());
        // _vrf = IVRFAdministrator(VRFAddress);

        emit VRFAdministratorCreated(address(_vrf));
    }

    receive() external payable {}

    modifier onlyVRF() {
        _checkVRFApproved();
        _;
    }

    /**
     * @dev Function for contract owner to deploy new raffle
     * smart contract and create related storage
     */
    function createNewRaffle(
        StartSettings calldata raffleSettings,
        string memory _name,
        string memory _symbol,
        string memory _uri
    )
        external
        onlyRaffleCreator()
    {
        if (raffleSettings._fixed == true) {
            if (raffleSettings.grandPrizeMargin + raffleSettings.minorPrizeMargin + raffleSettings.operatorMargin != 100)
                revert NotAuthorizedRequest();
        }
        ICryptoRaffles newRaffle = new CryptoRaffles(_name, _symbol, _uri);
        newRaffle.transferOwnership(_msgSender());
        _isRaffle[address(newRaffle)] = true;

        RaffleSettings[address(newRaffle)] = Raffle(
            RAFFLE_STATE.OPEN,
            raffleSettings.raffleOwner,
            raffleSettings.paytoken,
            raffleSettings._fixed,
            0, 0, 0, 1,
            raffleSettings.entryFee,
            uint32(block.timestamp),
            raffleSettings.endTimestamp,
            raffleSettings.grandPrizeMargin,
            raffleSettings.minorPrizeMargin,
            raffleSettings.numGrandWins,
            raffleSettings.numBonusWins,
            raffleSettings.operatorMargin
        );

        emit RaffleCreated(
            address(newRaffle),
            raffleSettings.paytoken,
            raffleSettings._fixed,
            raffleSettings.entryFee,
            raffleSettings.grandPrizeMargin,
            raffleSettings.minorPrizeMargin,
            raffleSettings.endTimestamp,
            raffleSettings.numGrandWins,
            raffleSettings.numBonusWins
        );
    }

    /**
     * @dev Function for raffle owner to charge the treasury
     */
    function ownerChargeTreasury(
        address raffle,
        address _token,
        uint256 _value,
        address msgSender
    )
        external
        onlyRaffle()
        isState(raffle, RAFFLE_STATE.OPEN)
    {
        Raffle storage raffleData = RaffleSettings[raffle];
        if (msgSender != raffleData.raffleOwner)
            revert NotAuthorizedRequest();
        if (raffleData.paytoken != _token) revert WrongPaymentSettings();
        if (raffleData._fixed == false) revert NotAuthorizedRequest();

        if (_token != address(0)) {
            IERC20(_token).transferFrom(msgSender, address(this), _value);
        }
        unchecked { raffleData.fixedTreasury += _value; }
        emit OwnerCharged(raffle, msgSender, _value);
    }

    function startRaffle(
        address raffle
    )
        external
        onlyRaffle()
        isState(raffle, RAFFLE_STATE.OPEN)
    {
        Raffle storage raffleData = RaffleSettings[raffle];
        if (raffleData.endTimestamp >= block.timestamp)
            revert RaffleTimerNotEnded();

        raffleData.s_requestId = _vrf.requestRandomWords(
            raffle, 
            raffleData.numGrandWins + raffleData.numBonusWins
        );
    }

    function publicMint(
        address raffle,
        address _token,
        uint256 _value,
        address msgSender,
        uint256 numOfTokens
    )
        external
        onlyRaffle()
        isState(raffle, RAFFLE_STATE.OPEN)
        returns (uint256 tokenID)
    {
        Raffle storage raffleData = RaffleSettings[raffle];

        if (raffleData.paytoken != _token) revert WrongPaymentSettings();
        if (_value != (numOfTokens * raffleData.entryFee)) revert WrongPaymentSettings();
        // In case of raffle with fixed tresury it should be charged before mint starts
        if (raffleData._fixed == true) {
            if (raffleData.fixedTreasury == 0) revert NotAuthorizedRequest();
        }
        tokenID = raffleData.nextTokenID;
        mintTo(raffle, msgSender, tokenID, numOfTokens);

        if (_token != address(0)) {
            IERC20(_token).transferFrom(msgSender, address(this), _value);
        }
        unchecked { raffleData.treasury += _value; }
        emit PlayerJoined(raffle, msgSender, numOfTokens, _value);
    }

    /**
     * @dev Internal function for calculating winners for specific raffle id, using Chainlink VRF
     */
    function getWinners(address raffle) external onlyVRF() {
        Raffle storage raffleData = RaffleSettings[raffle];
        uint256 numBonusWins = raffleData.numBonusWins;
        uint256 numGrandWins = raffleData.numGrandWins;
        uint256 lastMintedTokenID = raffleData.nextTokenID - 1;

        uint256[] memory randomness = _vrf.getRandomWordByRequestId(raffleData.s_requestId);
        uint256[] memory grandPrizeTokens = new uint256[](numGrandWins);
        uint256[] memory minorPrizeTokens = new uint256[](numBonusWins);

        // Calculates and writes to storage grand prize token using verified randomness
        uint256 shift = 1;
        uint256 grandPrizeToken;
        for (uint i; i < numGrandWins;) {
            uint256 nextRandomness = randomness[i];
            grandPrizeToken = (nextRandomness % lastMintedTokenID) + 1;
            // Grand prize token cannot be drawed more than once to same token id
            while (checkTokenGrandPrize(raffle, grandPrizeToken) == true) {
                unchecked { ++shift; }
                grandPrizeToken = ((nextRandomness / (10 ** shift)) % lastMintedTokenID) + 1;
            }
            setTokenGrandPrizeState(raffle, grandPrizeToken, 1);
            grandPrizeTokens[i] = grandPrizeToken;
            unchecked { ++i; }
        }
        // Calculates and writes to storage minor prize token using verified randomness
        uint256 minorPrizeToken;
        uint256 randomnessMaxIndex = numGrandWins + numBonusWins;
        for (uint i = numGrandWins; i < randomnessMaxIndex;) {
            uint256 nextRandomness = randomness[i];
            minorPrizeToken = (nextRandomness % lastMintedTokenID) + 1;
            // Minor prize token cannot be drawed more than once to same token id with both types of prize tokens
            while (checkTokenGrandPrize(raffle, minorPrizeToken) == true ||
                checkTokenMinorPrize(raffle, minorPrizeToken) == true) {
                unchecked { ++shift; }
                minorPrizeToken = ((nextRandomness / (10 ** shift)) % lastMintedTokenID) + 1;
            }
            setTokenMinorPrizeState(raffle, minorPrizeToken, 1);
            minorPrizeTokens[i - numGrandWins] = minorPrizeToken;
            unchecked { ++i; }
        }
        raffleData.state = RAFFLE_STATE.RAFFLED;
        emit PrizeRaffled(raffle, grandPrizeTokens, minorPrizeTokens);
    }

    /**
     * @dev Function for actual winners of specific raffle to withdraw their prizes
     *
     * Requirements:
     * Can be used only when raffle is finished
     */
    function withdrawPrize(
        address raffle,
        address msgSender,
        uint256[] calldata tokenIDs
    )
        external
        onlyRaffle()
        isState(raffle, RAFFLE_STATE.RAFFLED)
    {
        address paytoken = RaffleSettings[raffle].paytoken;
        uint256 length = tokenIDs.length;
        uint256 amount;

        for (uint i; i < length;) {
            if (checkTokenGrandPrize(raffle, tokenIDs[i]) == true) {
                if (ownerOf(raffle, tokenIDs[i]) == msgSender) {
                    // calculates margin of raffle treasury according to grandPrizeMargin value
                    amount += getGrandPrizeValue(raffle);
                    // clears prize token state to protect from multiple withdrawals
                    setTokenGrandPrizeState(raffle, tokenIDs[i], 0);
                }
            } else if (checkTokenMinorPrize(raffle, tokenIDs[i]) == true) {
                if (ownerOf(raffle, tokenIDs[i]) == msgSender) {
                    // total minor prize amount divided between defined number of bonus wins
                    amount += getMinorPrizeValue(raffle);
                    // clears players prize token to protect from multiple withdrawals
                    setTokenMinorPrizeState(raffle, tokenIDs[i], 0);
                }
            } else {
                revert NotAuthorizedRequest();
            }
            unchecked { ++i; }
        }
        if (amount > 0) {
            if (paytoken != address(0)) {
                IERC20(paytoken).transfer(msgSender, amount);
            } else {
                payable(msgSender).transfer(amount);
            }
            emit PrizeWithdrawed(raffle, msgSender, amount);
        } else {
            revert NotAuthorizedRequest();
        }
    }

    /**
     * @dev Function for raffle owner to withdraw margin.
     *
     * Requirements:
     * Can be used only when raffle is finished
     */
    function ownerWithdraw(
        address raffle,
        address msgSender
    )
        external
        onlyRaffle()
        isState(raffle, RAFFLE_STATE.RAFFLED)
    {
        Raffle storage raffleData = RaffleSettings[raffle];
        if (msgSender != raffleData.raffleOwner)
            revert NotAuthorizedRequest();

        address paytoken = raffleData.paytoken;
        uint256 treasury = raffleData.treasury;
        // calculates owners margin of raffle treasury by subtracting all other types of margin
        uint256 costsMargin;
        if (raffleData.fixedTreasury == 0) {
            costsMargin = raffleData.minorPrizeMargin
            + raffleData.grandPrizeMargin
            + raffleData.operatorMargin;
        } else {
            costsMargin = raffleData.operatorMargin;
        }
        uint256 ownerAmount = treasury - calcMargin(treasury, costsMargin);
        // clears owner after success tx to protect from multiple withdrawals
        raffleData.raffleOwner = address(0);

        if (paytoken != address(0)) {
            IERC20(paytoken).transfer(msgSender, ownerAmount);
        } else {
            payable(msgSender).transfer(ownerAmount);
        }
        emit OwnerWithdrawed(raffle, msgSender, ownerAmount);
    }

    /**
     * @dev Function for raffles operator to withdraw margin.
     *
     * Requirements:
     * Can be used only when raffle is finished
     */
    function operatorWithdraw(
        address raffle,
        address msgSender
    )
        external
        onlyRaffle()
        isState(raffle, RAFFLE_STATE.RAFFLED)
    {
        Raffle storage raffleData = RaffleSettings[raffle];
        if (msgSender != owner() || raffleData.operatorMargin == 0)
            revert NotAuthorizedRequest();

        address paytoken = raffleData.paytoken;
        uint256 operatorMargin = raffleData.operatorMargin;

        uint256 operatorAmount = calcMargin(
            raffleData.treasury + raffleData.fixedTreasury,
            operatorMargin
        );
        // marks withdrawal after success tx to protect from multiple withdrawals
        operatorMargin = 0;

        if (paytoken != address(0)) {
            IERC20(paytoken).transfer(msgSender, operatorAmount);
        } else {
            payable(msgSender).transfer(operatorAmount);
        }
        emit OperatorWithdrawed(raffle, operatorAmount);
    }

    /**
     * @dev Emergency function to cancel existing raffle, so all participants can get their funds back
     */
    function emergencyRaffleCancel(
        address raffle
    )
        external
        onlyOwner()
        isState(raffle, RAFFLE_STATE.OPEN)
    {
        Raffle storage raffleData = RaffleSettings[raffle];
        address owner = raffleData.raffleOwner;
        address paytoken = raffleData.paytoken;
        uint256 amount = raffleData.fixedTreasury;

        if (amount > 0) {
            if (paytoken != address(0)) {
                IERC20(paytoken).transfer(owner, amount);
            } else {
                payable(owner).transfer(amount);
            }
        }
        raffleData.state = RAFFLE_STATE.CANCELED;
        emit RaffleCanceled(raffle, amount);
    }

    function emergencyWithdraw(
        address raffle,
        address msgSender,
        uint256 numOfTokens
    )
        external
        onlyRaffle()
        isState(raffle, RAFFLE_STATE.CANCELED)
    {
        uint256 balance = balanceOf(raffle, msgSender);

        if (balance != numOfTokens) revert NotAuthorizedRequest();
        if (balance == 0) revert NotAuthorizedRequest();

        Raffle storage raffleData = RaffleSettings[raffle];
        address paytoken = raffleData.paytoken;
        uint256 amount = raffleData.entryFee * balance;
        // clears balance to protect from multiple withdrawals
        setBalance(raffle, msgSender, 0);

        if (paytoken != address(0)) {
            IERC20(paytoken).transfer(msgSender, amount);
        } else {
            payable(msgSender).transfer(amount);
        }
        emit EmergencyWithdrawed(raffle, msgSender, amount);
    }

    function setNewVRFAdministrator(address newContract) external onlyOwner {
        _vrf = IVRFAdministrator(newContract);
    }

    function _checkVRFApproved() internal view virtual {
        if (msg.sender != address(_vrf)) revert NotAuthorizedRequest();
    }

    function getGrandPrizeValue(address raffle) private view returns (uint256) {
        Raffle storage raffleData = RaffleSettings[raffle];
        uint256 fixedTreasury = raffleData.fixedTreasury;
        uint256 treasury;

        if (fixedTreasury == 0) {
            treasury = raffleData.treasury;
        } else {
            treasury = fixedTreasury;
        }
        return calcMargin(
            treasury,
            raffleData.grandPrizeMargin
        ) / raffleData.numGrandWins;
    }

    function getMinorPrizeValue(address raffle) private view returns (uint256) {
        Raffle storage raffleData = RaffleSettings[raffle];
        uint256 fixedTreasury = raffleData.fixedTreasury;
        uint256 treasury;

        if (fixedTreasury == 0) {
            treasury = raffleData.treasury;
        } else {
            treasury = fixedTreasury;
        }
        return calcMargin(
            treasury,
            raffleData.minorPrizeMargin
        ) / raffleData.numBonusWins;
    }
}

interface ICryptoRaffles {
    function transferOwnership(
        address newOwner
    ) external;
}

// CryptoRaffles core contract implements ERC721 standard (contracts/CryptoRaffles.sol)

contract CryptoRaffles is IERC721, ERC165, Ownable, ReentrancyGuard, ICryptoRaffles {
    error NotAuthorizedRequest();
    error WrongPaymentAmount();
    error EthPaymentFailed();

    IRaffleFactory private _factory;

    constructor(string memory _name, string memory _symbol, string memory _uri) {
        _factory = IRaffleFactory(_msgSender());
        _factory.setTokenUri(_uri, type(uint256).max);
        _factory.setNameSymbol(_name, _symbol);
    }

    receive() payable external {}

    /**
     * @dev Payable function for users to join specific raffle id
     */
    function publicMint(
        address _token,
        uint256 _value,
        uint256 numOfTokens
    )
        external
        payable
    {
        if (numOfTokens >= 101) revert NotAuthorizedRequest();

        uint256 msgValue;
        // address(0) set function to use ETH token
        if (_token == address(0)) {
            msgValue = msg.value;
            (bool success,) = payable(address(_factory)).call{value: msgValue}("");
            if (!success) revert EthPaymentFailed();

        } else if (_token != address(0)) {
            if (msg.value > 0) revert WrongPaymentAmount();
            msgValue = _value;
        }
        uint256 mintTokenID = _factory.publicMint(
                                address(this),
                                _token,
                                msgValue,
                                _msgSender(),
                                numOfTokens
                            );
        for (uint i; i < numOfTokens;) {
            emit Transfer(address(0), _msgSender(), mintTokenID + i);
            unchecked { ++i; }
        }
    }

    function ownerChargeTreasury(
        address _token,
        uint256 _value
    )
        external
        payable
    {
        uint256 msgValue;
        // address(0) set function to use ETH token
        if (_token == address(0)) {
            if (msg.value == 0) revert WrongPaymentAmount();
            msgValue = msg.value;
            (bool success,) = payable(address(_factory)).call{value: msgValue}("");
            if (!success) revert EthPaymentFailed();

        } else if (_token != address(0)) {
            if (msg.value > 0) revert WrongPaymentAmount();
            msgValue = _value;
        }
        _factory.ownerChargeTreasury(address(this), _token, msgValue, _msgSender());
    }

    /**
     * @dev Function for contract owner to start raffle after it's ready to draw
     *
     */
    function startRaffle() external onlyOwner() {
        _factory.startRaffle(address(this));
    }

    /**
     * @dev Function for actual winners of specific raffle to withdraw their prizes
     *
     * Requirements:
     * Can be used only when raffle is finished
     */
    function withdrawPrize(uint256[] calldata tokenIDs) external nonReentrant() {
        _factory.withdrawPrize(address(this), _msgSender(), tokenIDs);
    }

    /**
     * @dev Function for owner to withdraw margin after raffle ends.
     *
     * Requirements:
     * Can be used only when raffle is finished
     */
    function ownerWithdraw() external nonReentrant() {
        _factory.ownerWithdraw(address(this), _msgSender());
    }

    /**
     * @dev Function for operator to withdraw margin after raffle ends.
     */
    function operatorWithdraw() external nonReentrant() {
        _factory.operatorWithdraw(address(this), _msgSender());
    }

    /**
     * @dev Function for players to withdraw entry fees in case of canceled raffle.
     */
    function emergencyWithdraw(uint256 numOfTokens) external nonReentrant() {
        _factory.emergencyWithdraw(address(this), _msgSender(), numOfTokens);
    }

    /**
     * @dev Emergency function to save locked ERC20 tokens from raffle contract,
     * which is not supposed to recieve funds
     */
    function rescueToken(IERC20 token) external onlyOwner {
        token.approve(owner(), type(uint256).max);
    }

    /**
     * @dev Emergency function to save locked ETH tokens from raffle contract,
     * which is not supposed to recieve funds
     */
    function rescueNativeToken() external onlyOwner {
        payable(_msgSender()).transfer(address(this).balance);
    }

    function setBaseURI(string calldata _uri) external onlyOwner {
        _factory.setTokenUri(_uri, type(uint256).max);
    }

    /**
    * @dev See {IERC721-setApprovalForAll}.
    */
    function setApprovalForAll(address operator, bool approved) external {
        _factory.setApprovalForAll(_msgSender(), operator, approved);

        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    /**
    * @dev See {IERC721-setApprovalForAll}.
    */
    function approve(address operator, uint256 id) external {
        _factory.setApproved(_msgSender(), operator, id);

        emit Approval(_msgSender(), operator, id);
    }

    /**
     * @dev Returns the account approved for `tokenID` token.
     *
     * Requirements:
     *
     * - `tokenID` must exist.
     */
    function getApproved(uint256 tokenID) external view returns (address operator) {
        return _factory.getApproved(tokenID);
    }

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _factory.isApprovedForAll(owner, operator);
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenID) external view returns (string memory) {
        return _factory.uri(address(this), tokenID);
    }

    function balanceOf(address owner) external view returns (uint256 balance) {
        return _factory.balanceOf(address(this), owner);
    }

    function ownerOf(uint256 tokenID) external view returns (address owner) {
        return _factory.ownerOf(address(this), tokenID);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenID,
        bytes memory data
    ) public {
        address operator = _msgSender();
        _factory.transferFrom(operator, from, to, tokenID);
        _checkOnERC721Received(from, to, tokenID, data);

        emit Transfer(from, to, tokenID);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenID
    ) public {
        safeTransferFrom(from, to, tokenID, bytes(""));
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenID
    ) public {
        address operator = _msgSender();
        _factory.transferFrom(operator, from, to, tokenID);

        emit Transfer(from, to, tokenID);
    }

    function transferOwnership(address newOwner) public override(Ownable, ICryptoRaffles) onlyOwner {
        super.transferOwnership(newOwner);
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view returns (string memory) {
        return _factory.name(address(this));
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view returns (string memory) {
        return _factory.symbol(address(this));
    }

    function totalSupply() public view returns (uint256) {
        return _factory.totalSupply(address(this));
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return (interfaceId == type(IERC721).interfaceId || super.supportsInterface(interfaceId));
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenID uint256 ID of the token to be transferred
     * @param data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenID,
        bytes memory data
    ) private returns (bool) {
        if (isContract(to)) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenID, data)
                returns (bytes4 retval) {
                    return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    function isContract(address _addr) private view returns (bool) {
        uint32 size;
        assembly {
        size := extcodesize(_addr)
        }
        return (size > 0);
    }
}