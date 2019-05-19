pragma solidity ^0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/
    uint256 public constant REGISTRATION_FEE = 10 ether;
    uint public totalAirlines;
    address public firstAirline;
    bool public operational = true;

    address private contractOwner;

    struct UserProfile {
        bool authorized;
    }

    struct AirlineProfile {
        bool registered;
        bool funded;
    }

    struct Flight {
        bool registered;
        uint8 statusCode;
        uint256 timestamp;
        address airline;
        string flight;
        uint price;
        mapping(address => bool) bookings;
        mapping(address => uint) insurances;

    }

    mapping(address => UserProfile) public userProfiles;
    mapping(address => AirlineProfile) public airlineProfiles;
    mapping(address => uint) public withdrawals;
    mapping(bytes32 => Flight) public flights;

    address[] public passengers;

    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor(address _firstAirline) public {
        contractOwner = msg.sender;
        firstAirline = _firstAirline;
        airlineProfiles[firstAirline].registered = true;
        totalAirlines = 1;
    }

    event AirlineRegistered(address airline);
    event Funded(address airline);
    event FlightRegistered(address airline, string flight, uint256 timestamp, uint price);
    event Paid(address recipient, uint amount);
    event Credited(address passenger, uint amount);
    event BoughtTicket(address passenger, uint amount);

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in 
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational() {
        require(operational, "Contract is currently not operational");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    modifier isCallerAuthorized(address sender) {
        require(userProfiles[sender].authorized, "Caller is not authorized to call this function");
        _;
    }

    modifier isFlightRegistered(bytes32 flightKey) {
        require(flights[flightKey].registered, "This flight does not exist");
        _;
    }

    modifier notYetProcessed(bytes32 flightKey) {
        require(flights[flightKey].statusCode == 0, "This flight has already been processed");
        _;
    }

    modifier isAirline(address account){
        require(airlineProfiles[account].registered, "This airline is not registered yet");
        _;
    }

    modifier airlineFunded(address airline) {
        require(airlineProfiles[airline].funded, "Airline must provide funding");
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */      
    function isOperational() public view returns(bool) {
        return operational;
    }

    function isAirlineRegisterd(address airline) external view returns(bool) {
        return airlineProfiles[airline].registered;
    }

    function hasFunded(address airline) public view returns(bool) {
        return airlineProfiles[airline].funded;
    }

    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */    
    function setOperatingStatus(bool mode) external requireContractOwner {
        operational = mode;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    function authorizeCaller(address account) external requireIsOperational requireContractOwner {
        require(!userProfiles[account].authorized, "User is already authorized.");
        userProfiles[account] = UserProfile({authorized: true});
    }

   /**
    * @dev Add an airline to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */   
    //function registerAirline(address account) external requireIsOperational isCallerAuthorized(msg.sender) airlineFunded(account){
    function registerAirline(address airline) external requireIsOperational isCallerAuthorized(msg.sender) {
        airlineProfiles[airline].registered = true;
        totalAirlines += 1;
        emit AirlineRegistered(airline);
    }

    function registerFlight(string _flight, uint price, uint timestamp, address airline) external requireIsOperational isCallerAuthorized(msg.sender) airlineFunded(airline){
    //function registerFlight(string _flight, uint price, uint256 timestamp, address airline) external requireIsOperational isCallerAuthorized(msg.sender) {
        bytes32 flightKey = keccak256(abi.encodePacked(airline, _flight, timestamp));
        Flight memory flight = Flight(true, 0, timestamp, airline, _flight, price);
        flights[flightKey] = flight;
        emit FlightRegistered(airline, _flight, timestamp, price);
    }

    function processFlightStatus(bytes32 flightKey, uint8 statusCode) external isFlightRegistered(flightKey) requireIsOperational isCallerAuthorized(msg.sender) notYetProcessed(flightKey) {
    //function processFlightStatus(bytes32 flightKey, uint8 statusCode) external requireIsOperational isCallerAuthorized(msg.sender) notYetProcessed(flightKey) {
        Flight storage flight = flights[flightKey];
        flight.statusCode = statusCode;
        if (statusCode == 20) {
            creditInsurees(flightKey);
        }
    }

   /**
    * @dev Buy insurance for a flight
    *
    */   
    function buy(bytes32 flightKey, uint amount, address originAddress) external requireIsOperational isCallerAuthorized(msg.sender) payable {
        Flight storage flight = flights[flightKey];
        flight.bookings[originAddress] = true;
        flight.insurances[originAddress] = amount;
        passengers.push(originAddress);
        withdrawals[flight.airline] = flight.price;
        emit BoughtTicket(originAddress, amount);
    }

    /**
     *  @dev Credits payouts to insurees
    */
    function creditInsurees(bytes32 flightKey) internal requireIsOperational {
        emit Credited(msg.sender, 0);
        Flight storage flight = flights[flightKey];
        for (uint i = 0; i < passengers.length; i++) {
           withdrawals[passengers[i]] = flight.insurances[passengers[i]];
           emit Credited(passengers[i], flight.insurances[passengers[i]]);
        }
    }

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay(address originAddress) external requireIsOperational isCallerAuthorized(msg.sender) {
        require(withdrawals[originAddress] > 0, "No amount to be transferred to this address");
        uint amount = withdrawals[originAddress];
        withdrawals[originAddress] = 0;
        originAddress.transfer(amount);
        emit Paid(originAddress, amount);
    }

   /**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */   
    function fund(address originAddress) public requireIsOperational payable {
        require(msg.value == REGISTRATION_FEE, "Registration fee is required");
        require(airlineProfiles[originAddress].registered, "Must be registered to raise fund");
        airlineProfiles[originAddress].funded = true;
        emit Funded(originAddress);
    }

    function subscribedInsurance(address airline, string flight, uint256 timestamp, address passenger) public view returns(uint amount) {
        bytes32 flightKey = keccak256(abi.encodePacked(airline, flight, timestamp));
        return flights[flightKey].insurances[passenger];
    }

    /**
    * @dev Fallback function for funding smart contract.
    *
    */
    function() external payable {
        fund(msg.sender);
    }
}

