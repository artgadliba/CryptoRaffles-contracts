// SPDX-License-Identifier: None

pragma solidity 0.8.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

// Base contract designed to store all associated data (contracts/RaffleStorage.sol)

contract RaffleStorage is ReentrancyGuard, Ownable {
    bytes4 private immutable minorPrizeTokenStateSelector = bytes4(keccak256(bytes("minorPrizeTokenState()")));
    bytes4 private immutable grandPrizeTokenStateSelector = bytes4(keccak256(bytes("grandPrizeTokenState()")));

    enum RAFFLE_STATE {
        OPEN,
        RAFFLED,
        CANCELED
    }

    struct Raffle {
        RAFFLE_STATE state;
        address raffleOwner;
        address paytoken;
        uint256 s_requestId;
        uint256 treasury;
        uint32 numOfPlayers;
        uint32 startTime;
        uint32 endTimestamp;
        uint32 grandPrizeMargin;
        uint32 minorPrizeMargin;
        uint32 numGrandWins;
        uint32 numBonusWins;
        uint32 operatorMargin;
    }

    mapping(address => Raffle) internal RaffleSettings;
    mapping(address => bytes32) internal RaffleMerkle;
    mapping(address => bool) internal _isRaffle;

    mapping(address => mapping(bytes4 => mapping(address => mapping(uint256 => bool)))) private _storage;

    event RaffleCreated(
        address indexed raffleAddress,
        address owner,
        address paytoken, 
        uint256 startTime, 
        uint32 endTimestamp, 
        uint32 grandPrizeMargin, 
        uint32 minorPrizeMargin,
        uint32 numGrandsWins,
        uint32 numBonusWins
    );
    event RaffleCanceled(address indexed raffleAddress, uint256 amount);
    event PrizeRaffled(address indexed raffleAddress, uint256[] grandPrizeTokens, uint256[] minorPrizeTokens);
    event PrizeWithdrawed(address indexed raffleAddress, address indexed player, uint256 amount);
    event OwnerCharged(address indexed raffleAddress, address indexed owner, uint256 amount);
    event OperatorWithdrawed(address indexed raffleAddress, uint256 amount);

    error NotAuthorizedRequest();
    error WrongRaffleState();
    error WrongPaymentSettings();
    error RaffleTimerNotEnded();
    error RaffleTreasuryNotCharged();
    error WrongaRaffleSettings();

    modifier isState(address raffle, RAFFLE_STATE state) {
        _checkState(raffle, state);
        _;
    }

    modifier onlyRaffle() {
        _checkRaffleApproved();
        _;
    }

    function write(address raffle, bytes4 selector, address player, uint256 key, bool state) internal {
        _storage[raffle][selector][player][key] = state;
    }

    function setTokenMinorPrizeState(address raffle, uint256 tokenID, bool state) internal {
        write(raffle, minorPrizeTokenStateSelector, address(0), tokenID, state);
    }

    function setTokenGrandPrizeState(address raffle, uint256 tokenID, bool state) internal {
        write(raffle, grandPrizeTokenStateSelector, address(0), tokenID, state);
    }

    function isRaffle(address raffle) internal view returns (bool) {
            return _isRaffle[raffle];
    }

    function read(address raffle, bytes4 selector, address player, uint256 key) internal view
        returns (bool) {
            return _storage[raffle][selector][player][key];
    }

    function checkTokenMinorPrize(address raffle, uint256 tokenID) internal view returns (bool) {
        return read(raffle, minorPrizeTokenStateSelector, address(0), tokenID);
    }

    function checkTokenGrandPrize(address raffle, uint256 tokenID) internal view returns (bool) {
        return read(raffle, grandPrizeTokenStateSelector, address(0), tokenID);
    }

    function _checkRaffleApproved() internal view virtual {
        if(!isRaffle(msg.sender)) revert NotAuthorizedRequest();
    }

    function _checkState(address raffle, RAFFLE_STATE state) internal view virtual {
        if(RaffleSettings[raffle].state != state) revert WrongRaffleState();
    }

    /**
     * @dev Internal function to calculate margin, using defined at Raffle creation variables
     * Returned value will be used to proceed withdrow functions
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

    function getRandomWordByRequestId(
        uint256 requestId
    ) external returns (uint256[] memory);

    function transferOwnership(
        address newOwner
    ) external;
}

// Custom contract for Chainlink's verified randomness consumer control

contract VRFAdministrator is IVRFAdministrator, VRFConsumerBaseV2, Ownable {
    IRaffleFactory private _factory;
    VRFCoordinatorV2Interface private COORDINATOR;

    bytes32 private keyHash = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;

    uint64 private s_subscriptionId;
    uint32 private callbackGasLimit = 500000;
    uint16 private constant REQUEST_CONFIRMATIONS = 5;

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
     * @dev Internal function to request randomness for specific raffle
     */
    function requestRandomWords(
        address raffle,
        uint32 _numWords
    ) external returns(uint256 _requestId) {
        if (msg.sender != address(_factory)) revert NotAuthorizedRequest();

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
        address _raffleAddress = requestIdToRaffleAddress[requestId];
        _factory.getWinners(_raffleAddress);

        emit RandomWordsFulfilled(requestId, randomWords);
    }
}

interface IRaffleFactory {
    function startRaffle(
        address raffle,
        uint32 _numOfPlayers
    ) external;

    function setRaffleRequestId(
        address raffle,
        uint256 requestId
    ) external;

    function getWinners(address raffle) external;

    function ownerChargeTreasury(
        address raffle,
        address _token,
        uint256 _value,
        address msgSender
    ) external;

    function withdrawPrize(
        address raffle,
        address msgSender,
        uint256 prizeToken,
        bytes32[] calldata proof
    ) external;

    function operatorWithdraw(
        address raffle,
        address msgSender
    ) external;

    function emergencyRaffleCancel(
        address raffle,
        address msgSender
    ) external;
}

interface IRaffleSettings {
    struct StartSettings {
        address raffleOwner;
        address paytoken;
        uint32 endTimestamp;
        uint32 grandPrizeMargin;
        uint32 minorPrizeMargin;
        uint32 numGrandWins;
        uint32 numBonusWins;
        uint32 operatorMargin;
    }
}

// Factory style contract to deploy and control different raffles

contract RaffleFactory is RaffleStorage, IRaffleSettings {
    IVRFAdministrator private _vrf;

    address private merkleAdministrator;

    event VRFAdministratorRegistered(address vrfAddress);

    error NotAllowedToChangeMerkleRoot();
    error MerkleRootNotSet();

    // move out hardcoded values from constructor in PROD ver.
    constructor(address merkleAdmin) {
        _vrf = new VRFAdministrator(
            1058,
            0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625, // Sepolia testnet coordinator contract
            address(this)
        );
        _vrf.transferOwnership(_msgSender());
        // _vrf = IVRFAdministrator(VRFAddress);
        merkleAdministrator = merkleAdmin;

        emit VRFAdministratorRegistered(address(_vrf));
    }

    receive() payable external {}

    modifier onlyVRF() {
        _checkVRFApproved();
        _;
    }

    modifier onlyOwnerOrMerkleAdmin() {
        _checkOwnerOrMerkleAdmin();
        _;
    }

    /**
     * @dev Function for contract owner to deploy new raffle
     * smart contract and create related storage
     */
    function createNewRaffle(
        StartSettings calldata raffleSettings
    )
        external
        onlyOwner()
    {
        if (raffleSettings.grandPrizeMargin + raffleSettings.minorPrizeMargin + raffleSettings.operatorMargin != 100)
            revert WrongaRaffleSettings();

        ICryptoRaffles newRaffle = new CryptoRaffles();
        newRaffle.transferOwnership(_msgSender());
        _isRaffle[address(newRaffle)] = true;

        RaffleSettings[address(newRaffle)] = Raffle(
            RAFFLE_STATE.OPEN,
            raffleSettings.raffleOwner,
            raffleSettings.paytoken,
            0, 0, 0,
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
            raffleSettings.raffleOwner,
            raffleSettings.paytoken,
            block.timestamp,
            raffleSettings.endTimestamp,
            raffleSettings.grandPrizeMargin,
            raffleSettings.minorPrizeMargin,
            raffleSettings.numGrandWins,
            raffleSettings.numBonusWins
        );
    }

    function startRaffle(
        address raffle,
        uint32 _numOfPlayers
    )
        external
        onlyRaffle()
        isState(raffle, RAFFLE_STATE.OPEN)
    {
        Raffle storage raffleData = RaffleSettings[raffle];
        // Raffle end timer in seconds should be greater than current block time to start raffle
        if (raffleData.endTimestamp >= block.timestamp)
            revert RaffleTimerNotEnded();
        // Raffle treasury must be charged to start raffle
        if (raffleData.treasury == 0) revert RaffleTreasuryNotCharged();
        // Merkle root must be set before raffle can be started
        if (RaffleMerkle[raffle] == 0) revert MerkleRootNotSet();

        raffleData.numOfPlayers = _numOfPlayers;
        raffleData.s_requestId = _vrf.requestRandomWords(raffle, raffleData.numGrandWins + raffleData.numBonusWins);
    }

    function getRequestId(address raffle) external view returns (uint256) {
        return RaffleSettings[raffle].s_requestId;
    }

    /**
     * @dev Internal function for calculating winners for specific raffle, using Chainlink VRF
     */
    function getWinners(address raffle) external onlyVRF() {
        Raffle storage raffleData = RaffleSettings[raffle];
        uint256 numGrandWins = raffleData.numGrandWins;
        uint256 numBonusWins = raffleData.numBonusWins;
        uint256 numOfPlayers = raffleData.numOfPlayers;

        uint256[] memory randomness = _vrf.getRandomWordByRequestId(raffleData.s_requestId);
        uint256[] memory grandPrizeTokens = new uint256[](numGrandWins);
        uint256[] memory minorPrizeTokens = new uint256[](numBonusWins);

        // Calculates and writes to storage grand prize token using verified randomness
        uint256 grandPrizeToken;
        uint256 shift = 1;
        for (uint i; i < numGrandWins;) {
            uint256 nextRandomness = randomness[i];
            grandPrizeToken = (nextRandomness % numOfPlayers) + 1;
            // Grand prize token cannot be drawed more than once to same token id
            while (checkTokenGrandPrize(raffle, grandPrizeToken) == true) {
                unchecked { ++shift; }
                grandPrizeToken = ((nextRandomness / (10 ** shift)) % numOfPlayers) + 1;
            }
            setTokenGrandPrizeState(raffle, grandPrizeToken, true);
            grandPrizeTokens[i] = grandPrizeToken;
            unchecked { ++i; }
        }
        uint256 minorPrizeToken;
        // Calculates and writes to storage minor prize token using verified randomness
        uint256 randomnessMaxIndex = numGrandWins + numBonusWins;
        for (uint i = numGrandWins; i < randomnessMaxIndex;) {
            uint256 nextRandomness = randomness[i];
            minorPrizeToken = (nextRandomness % numOfPlayers) + 1;
            // Minor prize token cannot be the same as grand prize token or drawed more than once to same token id
            while (checkTokenGrandPrize(raffle, minorPrizeToken) == true || 
                checkTokenMinorPrize(raffle, minorPrizeToken) == true) {
                unchecked { ++shift; }
                minorPrizeToken = ((nextRandomness / (10 ** shift)) % numOfPlayers) + 1;
            }
            setTokenMinorPrizeState(raffle, minorPrizeToken, true);
            minorPrizeTokens[i - numGrandWins] = minorPrizeToken;
            unchecked { ++i; }
        }
        raffleData.state = RAFFLE_STATE.RAFFLED;
        emit PrizeRaffled(raffle, grandPrizeTokens, minorPrizeTokens);
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

        if (_token != address(0)) {
            IERC20(_token).transferFrom(msgSender, address(this), _value);
        }
        unchecked { raffleData.treasury += _value; }
        emit OwnerCharged(raffle, msgSender, _value);
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
        uint256 prizeToken,
        bytes32[] calldata proof
    )
        external
        onlyRaffle()
        isState(raffle, RAFFLE_STATE.RAFFLED)
    {
        Raffle storage raffleData = RaffleSettings[raffle];
        bytes32 node = keccak256(abi.encodePacked(msgSender, prizeToken));
        address paytoken = raffleData.paytoken;

        if (MerkleProof.verify(proof, RaffleMerkle[raffle], node) != true) revert NotAuthorizedRequest();
        if (checkTokenGrandPrize(raffle, prizeToken) == true) {
            uint256 grandAmount = calcMargin(
                raffleData.treasury,
                raffleData.grandPrizeMargin
            ) / raffleData.numGrandWins;

            // clear prize token after success tx to protect from multiple withdrawals
            setTokenGrandPrizeState(raffle, prizeToken, false);
            if (paytoken != address(0)) {
                IERC20(paytoken).transfer(msgSender, grandAmount);
            } else {
                payable(msgSender).transfer(grandAmount);
            }
            emit PrizeWithdrawed(raffle, msgSender, grandAmount);

        } else if (checkTokenMinorPrize(raffle, prizeToken) == true) {
            uint256 minorAmount = calcMargin(
                raffleData.treasury,
                raffleData.minorPrizeMargin) / raffleData.numBonusWins;

            // clear prize token after success tx to protect from multiple withdrawals
            setTokenMinorPrizeState(raffle, prizeToken, false);
            if (paytoken != address(0)) {
                IERC20(paytoken).transfer(msgSender, minorAmount);
            } else {
                payable(msgSender).transfer(minorAmount);
            }
            emit PrizeWithdrawed(raffle, msgSender, minorAmount);
            
        } else {
            revert NotAuthorizedRequest();
        }
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

        uint256 operatorAmount = calcMargin(
            raffleData.treasury,
            raffleData.operatorMargin
        );
        address paytoken = raffleData.paytoken;
        // marks withdrawal after success tx to protect from multiple withdrawals
        raffleData.operatorMargin = 0;

        if (paytoken != address(0)) {
            IERC20(paytoken).transfer(msgSender, operatorAmount);
        } else {
            payable(msgSender).transfer(operatorAmount);
        }
        emit OperatorWithdrawed(raffle, operatorAmount);
    }

    /**
     * @dev Emergency function to cancel existing raffle
     */
    function emergencyRaffleCancel(
        address raffle,
        address msgSender
    )
        external
        onlyRaffle()
        isState(raffle, RAFFLE_STATE.OPEN)
    {
        Raffle storage raffleData = RaffleSettings[raffle];
        if (msgSender != raffleData.raffleOwner)
            revert NotAuthorizedRequest();
        // Raffle can be emergency canceled only within 24 hours from beggining
        if (raffleData.startTime + 24 hours <= block.timestamp)
            revert RaffleTimerNotEnded();

        uint256 amount = raffleData.treasury;
        address paytoken = raffleData.paytoken;

        if (paytoken != address(0)) {
            IERC20(paytoken).transfer(msgSender, amount);
        } else {
            payable(msgSender).transfer(amount);
        }
        raffleData.state = RAFFLE_STATE.CANCELED;
        emit RaffleCanceled(raffle, amount);
    }

    function setMerkleAdministrator(address newAdmin) external onlyOwner() {
        merkleAdministrator = newAdmin;
    }

    /**
     * @dev Function for factory owner to set Merkle root for specific raffle
     * Requirements: Can be set only once per each raffle. So operator can't manipulate whitelsit
     */
    function setRaffleMerkleRoot(
        address raffle,
        bytes32 root
    )
        external
        onlyOwnerOrMerkleAdmin()
    {
        if (RaffleMerkle[raffle] != 0)
            revert NotAllowedToChangeMerkleRoot();
        RaffleMerkle[raffle] = root;
    }

    function _checkVRFApproved() internal view virtual {
        if (msg.sender != address(_vrf)) revert NotAuthorizedRequest();
    }

    function _checkOwnerOrMerkleAdmin() internal view virtual {
        if (msg.sender != owner()) {
            if (msg.sender != merkleAdministrator)
                revert NotAuthorizedRequest();
        }
    }
}

interface ICryptoRaffles {
    function transferOwnership(
        address newOwner
    ) external;
}

// CryptoRaffles core contract designed to interact with specific raffle (contracts/CryptoRaffles.sol)

contract CryptoRaffles is ERC165, Ownable, ReentrancyGuard, ICryptoRaffles {
    error EthPaymentFailed();
    error WrongPaymentAmount();

    IRaffleFactory private _factory;

    constructor() {
        _factory = IRaffleFactory(msg.sender);
    }

    receive() payable external {}

    /**
     * @dev Function for contract owner to start raffle after it's ready to draw
     */
    function startRaffle(
        uint32 _numOfPlayers
    )
        external
        onlyOwner()
    {
        _factory.startRaffle(address(this), _numOfPlayers);
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
            msgValue = _value;
            if (msg.value > 0) revert WrongPaymentAmount();
        }
        _factory.ownerChargeTreasury(address(this), _token, msgValue, _msgSender());
    }

    /**
     * @dev Function for actual winners of specific raffle to withdraw their prizes
     *
     * Requirements:
     * Can be used only when raffle is finished
     */
    function withdrawPrize(
        uint256 prizeToken,
        bytes32[] memory proof
    )
        external
        nonReentrant()
    {
        _factory.withdrawPrize(address(this), _msgSender(), prizeToken, proof);
    }

    /**
     * @dev Function for operator to withdraw margin after raffle ends.
     */
    function operatorWithdraw()
        external
        onlyOwner()
        nonReentrant()
    {
        _factory.operatorWithdraw(address(this), _msgSender());
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

    /**
     * @dev Emergency function to cancel existing raffle
     */
    function emergencyRaffleCancel() external nonReentrant() {
        _factory.emergencyRaffleCancel(address(this), _msgSender());
    }

    function transferOwnership(address newOwner) public override(Ownable, ICryptoRaffles) {
        super.transferOwnership(newOwner);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165) returns (bool) {
        return (super.supportsInterface(interfaceId));
    }
}
