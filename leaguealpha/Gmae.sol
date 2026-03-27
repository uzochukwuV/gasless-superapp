// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title GameEngine
 * @notice Manages match generation, VRF randomness, and season lifecycle
 * @dev 20 teams, 10 matches per round, 36 rounds per season
 * @dev Uses Chainlink VRF v2.5 Subscription-based - coordinator handles funding
 */
contract GameEngine is VRFConsumerBaseV2Plus {
    LinkTokenInterface public immutable linkToken;

    // VRF configuration
    uint256 public s_subscriptionId;
    bytes32 public keyHash = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae; // Sepolia gas lane
    uint32 public callbackGasLimit = 2000000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = uint32(MATCHES_PER_ROUND); // 1 random word per match; derive two scores per match

    // Game constants
    uint256 public constant TEAMS_COUNT = 20;
    uint256 public constant MATCHES_PER_ROUND = 10;
    uint256 public constant ROUNDS_PER_SEASON = 36;
    uint256 public constant ROUND_DURATION = 3 hours; // Changed from 15 minutes to 3 hours

    enum MatchOutcome {
        PENDING,
        HOME_WIN,
        AWAY_WIN,
        DRAW
    }

    struct Match {
        uint256 homeTeamId;
        uint256 awayTeamId;
        uint8 homeScore;
        uint8 awayScore;
        MatchOutcome outcome;
        bool settled;
        // Odds removed - betting odds are managed by BettingPool
    }

    struct Team {
        string name;
        uint256 wins;
        uint256 draws;
        uint256 losses;
        uint256 points; // 3 for win, 1 for draw, 0 for loss
        uint256 goalsFor;
        uint256 goalsAgainst;
    }

    struct Season {
        uint256 seasonId;
        uint256 startTime;
        uint256 currentRound;
        bool active;
        bool completed;
        uint256 winningTeamId;
    }

    struct Round {
        uint256 roundId;
        uint256 seasonId;
        uint256 startTime;
        uint256 vrfRequestId;
        bool settled;
        Match[MATCHES_PER_ROUND] matches;
    }

    struct RequestStatus {
        bool exists; // whether the request exists
        bool fulfilled;
        uint256 roundId;
    }

    struct TestVRFRequest {
        bool exists;
        bool fulfilled;
        uint256 requestTime;
        uint256[] randomWords;
    }

    // State
    uint256 public currentSeasonId;
    uint256 public currentRoundId;

    // VRF failure handling
    uint256 public constant VRF_TIMEOUT = 2 hours;
    mapping(uint256 => uint256) public roundVRFRequestTime;

    mapping(uint256 => Season) public seasons;
    mapping(uint256 => Round) public rounds;
    mapping(uint256 => Team) public teams;
    mapping(uint256 => mapping(uint256 => Team)) public seasonStandings; // seasonId => teamId => Team stats
    mapping(uint256 => RequestStatus) public vrfRequests; // VRF requestId => RequestStatus

    // VRF Testing
    mapping(uint256 => TestVRFRequest) public testVRFRequests; // requestId => TestVRFRequest
    uint256 public lastTestRequestId;

    // Events
    event SeasonStarted(uint256 indexed seasonId, uint256 startTime);
    event SeasonEnded(uint256 indexed seasonId, uint256 winningTeamId);
    event RoundStarted(uint256 indexed roundId, uint256 indexed seasonId, uint256 startTime);
    event RoundSettled(uint256 indexed roundId, uint256 indexed seasonId);
    event MatchSettled(
        uint256 indexed roundId,
        uint256 matchIndex,
        uint256 homeTeamId,
        uint256 awayTeamId,
        uint8 homeScore,
        uint8 awayScore,
        MatchOutcome outcome
    );
    event VRFRequested(uint256 indexed roundId, uint256 requestId, uint256 paid);
    event VRFFulfilled(uint256 indexed requestId, uint256 indexed roundId);
    event TestVRFRequested(uint256 indexed requestId, uint256 timestamp);
    event TestVRFFulfilled(uint256 indexed requestId, uint256[] randomWords);

    /**
     * @notice Constructor
     * @param _linkAddress LINK token address (Sepolia: 0x779877A7B0D9E8603169DdbD7836e478b4624789)
     * @param _subscriptionId VRF subscription ID
     */
    constructor(
        address _linkAddress,
        uint256 _subscriptionId
    ) VRFConsumerBaseV2Plus(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B) {
        linkToken = LinkTokenInterface(_linkAddress);
        s_subscriptionId = _subscriptionId;
        _initializeTeams();
    }

    /**
     * @notice Initialize the 20 team names
     */
    function _initializeTeams() private {
        teams[0] = Team("Manchester Virtual", 0, 0, 0, 0, 0, 0);
        teams[1] = Team("Liverpool Digital", 0, 0, 0, 0, 0, 0);
        teams[2] = Team("Chelsea Crypto", 0, 0, 0, 0, 0, 0);
        teams[3] = Team("Arsenal Web3", 0, 0, 0, 0, 0, 0);
        teams[4] = Team("Tottenham Chain", 0, 0, 0, 0, 0, 0);
        teams[5] = Team("Manchester Block", 0, 0, 0, 0, 0, 0);
        teams[6] = Team("Newcastle Node", 0, 0, 0, 0, 0, 0);
        teams[7] = Team("Brighton Token", 0, 0, 0, 0, 0, 0);
        teams[8] = Team("Aston Meta", 0, 0, 0, 0, 0, 0);
        teams[9] = Team("West Ham Hash", 0, 0, 0, 0, 0, 0);
        teams[10] = Team("Everton Ether", 0, 0, 0, 0, 0, 0);
        teams[11] = Team("Leicester Link", 0, 0, 0, 0, 0, 0);
        teams[12] = Team("Wolves Wallet", 0, 0, 0, 0, 0, 0);
        teams[13] = Team("Crystal Palace Protocol", 0, 0, 0, 0, 0, 0);
        teams[14] = Team("Fulham Fork", 0, 0, 0, 0, 0, 0);
        teams[15] = Team("Brentford Bridge", 0, 0, 0, 0, 0, 0);
        teams[16] = Team("Bournemouth Bytes", 0, 0, 0, 0, 0, 0);
        teams[17] = Team("Nottingham NFT", 0, 0, 0, 0, 0, 0);
        teams[18] = Team("Southampton Smart", 0, 0, 0, 0, 0, 0);
        teams[19] = Team("Leeds Ledger", 0, 0, 0, 0, 0, 0);
    }

    /**
     * @notice Start a new season
     */
    function startSeason() external onlyOwner {
        require(
            currentSeasonId == 0 || seasons[currentSeasonId].completed,
            "Season already active"
        );

        currentSeasonId++;

        seasons[currentSeasonId] = Season({
            seasonId: currentSeasonId,
            startTime: block.timestamp,
            currentRound: 0,
            active: true,
            completed: false,
            winningTeamId: 0
        });

        // Reset team standings for new season
        for (uint256 i = 0; i < TEAMS_COUNT; i++) {
            seasonStandings[currentSeasonId][i] = Team({
                name: teams[i].name,
                wins: 0,
                draws: 0,
                losses: 0,
                points: 0,
                goalsFor: 0,
                goalsAgainst: 0
            });
        }

        emit SeasonStarted(currentSeasonId, block.timestamp);
    }

    /**
     * @notice Start a new round (generates 10 matches with random pairings)
     */
    function startRound() external onlyOwner {
        require(seasons[currentSeasonId].active, "No active season");
        require(
            currentRoundId == 0 || rounds[currentRoundId].settled,
            "Previous round not settled"
        );
        require(
            seasons[currentSeasonId].currentRound < ROUNDS_PER_SEASON,
            "Season completed"
        );

        currentRoundId++;
        seasons[currentSeasonId].currentRound++;

        Round storage newRound = rounds[currentRoundId];
        newRound.roundId = currentRoundId;
        newRound.seasonId = currentSeasonId;
        newRound.startTime = block.timestamp;
        newRound.settled = false;

        // Generate random team pairings using pseudo-randomness for pairing only
        // (actual scores will come from VRF)
        uint256[] memory shuffledTeams = _shuffleTeams(currentRoundId);

        for (uint256 i = 0; i < MATCHES_PER_ROUND; i++) {
            uint256 homeId = shuffledTeams[i * 2];
            uint256 awayId = shuffledTeams[i * 2 + 1];

            // Odds are now managed by BettingPool, not GameEngine
            newRound.matches[i] = Match({
                homeTeamId: homeId,
                awayTeamId: awayId,
                homeScore: 0,
                awayScore: 0,
                outcome: MatchOutcome.PENDING,
                settled: false
            });
        }

        emit RoundStarted(currentRoundId, currentSeasonId, block.timestamp);
    }

    /**
     * @notice Request VRF randomness to settle match scores
     * @dev Uses VRF v2.5 Subscription-based
     * @param enableNativePayment Set to true to pay in native ETH, false for LINK
     */
    function requestMatchResults(bool enableNativePayment) external onlyOwner returns (uint256 requestId) {
        require(!rounds[currentRoundId].settled, "Round already settled");
        require(
            block.timestamp >= rounds[currentRoundId].startTime + ROUND_DURATION,
            "Round duration not elapsed"
        );

        // Request random words from coordinator
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: enableNativePayment})
                )
            })
        );

        // Store request info
        vrfRequests[requestId] = RequestStatus({
            exists: true,
            fulfilled: false,
            roundId: currentRoundId
        });

        rounds[currentRoundId].vrfRequestId = requestId;
        roundVRFRequestTime[currentRoundId] = block.timestamp;

        emit VRFRequested(currentRoundId, requestId, 0);

        return requestId;
    }

    /**
     * @notice Request random sample to test VRF (for testing purposes)
     * @param enableNativePayment Set to true to pay in native ETH, false for LINK
     * @param wordsToRequest Number of random words to request (1-10)
     * @return requestId The VRF request ID
     */
    function requestRandomSample(bool enableNativePayment, uint32 wordsToRequest)
        external
        onlyOwner
        returns (uint256 requestId)
    {
        require(wordsToRequest > 0 && wordsToRequest <= 10, "numWords must be 1-10");

        // Request random words from coordinator
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: wordsToRequest,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: enableNativePayment})
                )
            })
        );

        // Store test request info
        testVRFRequests[requestId] = TestVRFRequest({
            exists: true,
            fulfilled: false,
            requestTime: block.timestamp,
            randomWords: new uint256[](0)
        });

        lastTestRequestId = requestId;

        emit TestVRFRequested(requestId, block.timestamp);

        return requestId;
    }

    /**
     * @notice Chainlink VRF v2.5 callback - settles match results or test requests
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) internal override {
        // Check if this is a test VRF request
        if (testVRFRequests[requestId].exists) {
            TestVRFRequest storage testRequest = testVRFRequests[requestId];
            require(!testRequest.fulfilled, "Test request already fulfilled");

            // Mark as fulfilled and store random words
            testRequest.fulfilled = true;

            // Copy random words to storage
            for (uint256 i = 0; i < randomWords.length; i++) {
                testRequest.randomWords.push(randomWords[i]);
            }

            emit TestVRFFulfilled(requestId, randomWords);
            return;
        }

        // Otherwise, handle normal round settlement
        RequestStatus storage request = vrfRequests[requestId];
        require(request.exists, "Invalid request ID");
        require(!request.fulfilled, "Already fulfilled");

        uint256 roundId = request.roundId;
        Round storage round = rounds[roundId];
        require(!round.settled, "Already settled");

        // Mark as fulfilled
        request.fulfilled = true;

        // Defensive check: ensure randomWords array has expected length
        require(randomWords.length == MATCHES_PER_ROUND, "Incorrect number of random words");

        for (uint256 i = 0; i < MATCHES_PER_ROUND; i++) {
            Match storage _match = round.matches[i];

            // Use 1 random word per match and derive two scores (away derived by hashing word + index)
            uint256 word = randomWords[i];
            uint8 homeScore = _generateScore(word);
            uint8 awayScore = _generateScore(uint256(keccak256(abi.encodePacked(word, i))));

            _match.homeScore = homeScore;
            _match.awayScore = awayScore;
            _match.settled = true;

            // Determine outcome
            if (homeScore > awayScore) {
                _match.outcome = MatchOutcome.HOME_WIN;
            } else if (awayScore > homeScore) {
                _match.outcome = MatchOutcome.AWAY_WIN;
            } else {
                _match.outcome = MatchOutcome.DRAW;
            }

            // Update season standings
            _updateStandings(round.seasonId, _match);

            emit MatchSettled(
                roundId,
                i,
                _match.homeTeamId,
                _match.awayTeamId,
                homeScore,
                awayScore,
                _match.outcome
            );
        }

        round.settled = true;
        emit VRFFulfilled(requestId, roundId);
        emit RoundSettled(roundId, round.seasonId);

        // Check if season is complete
        if (seasons[round.seasonId].currentRound >= ROUNDS_PER_SEASON) {
            _endSeason(round.seasonId);
        }
    }

    /**
     * @notice Generate realistic football score from random word
     */
    function _generateScore(uint256 randomWord) private pure returns (uint8) {
        uint256 roll = randomWord % 100;

        // Weighted probabilities for realistic scores
        if (roll < 15) return 0; // 15%
        if (roll < 40) return 1; // 25%
        if (roll < 65) return 2; // 25%
        if (roll < 82) return 3; // 17%
        if (roll < 93) return 4; // 11%
        return 5; // 7%
    }

    /**
     * @notice Shuffle teams for random match pairings
     */
    function _shuffleTeams(uint256 seed) private pure returns (uint256[] memory) {
        uint256[] memory teamIds = new uint256[](TEAMS_COUNT);
        for (uint256 i = 0; i < TEAMS_COUNT; i++) {
            teamIds[i] = i;
        }

        // Fisher-Yates shuffle
        for (uint256 i = TEAMS_COUNT - 1; i > 0; i--) {
            uint256 j = uint256(keccak256(abi.encodePacked(seed, i))) % (i + 1);
            (teamIds[i], teamIds[j]) = (teamIds[j], teamIds[i]);
        }

        return teamIds;
    }

    /**
     * @notice Update season standings based on match result
     */
    function _updateStandings(uint256 seasonId, Match memory _match) private {
        Team storage homeTeam = seasonStandings[seasonId][_match.homeTeamId];
        Team storage awayTeam = seasonStandings[seasonId][_match.awayTeamId];

        homeTeam.goalsFor += _match.homeScore;
        homeTeam.goalsAgainst += _match.awayScore;
        awayTeam.goalsFor += _match.awayScore;
        awayTeam.goalsAgainst += _match.homeScore;

        if (_match.outcome == MatchOutcome.HOME_WIN) {
            homeTeam.wins++;
            homeTeam.points += 3;
            awayTeam.losses++;
        } else if (_match.outcome == MatchOutcome.AWAY_WIN) {
            awayTeam.wins++;
            awayTeam.points += 3;
            homeTeam.losses++;
        } else {
            homeTeam.draws++;
            awayTeam.draws++;
            homeTeam.points += 1;
            awayTeam.points += 1;
        }
    }

    /**
     * @notice End the season and determine winner
     */
    function _endSeason(uint256 seasonId) private {
        Season storage season = seasons[seasonId];
        season.active = false;
        season.completed = true;

        // Find team with highest points
        uint256 winningTeamId = 0;
        uint256 maxPoints = 0;

        for (uint256 i = 0; i < TEAMS_COUNT; i++) {
            if (seasonStandings[seasonId][i].points > maxPoints) {
                maxPoints = seasonStandings[seasonId][i].points;
                winningTeamId = i;
            }
        }

        season.winningTeamId = winningTeamId;
        emit SeasonEnded(seasonId, winningTeamId);
    }

    /**
     * @notice Calculate initial odds based on team season performance
     * @dev Odds are scaled by 100 (e.g., 150 = 1.5x payout)
     */
    // Odds calculation removed - now handled by BettingPool
    // GameEngine only manages matches and VRF results

    // View functions for frontend
    function getCurrentRound() external view returns (uint256) {
        return currentRoundId;
    }

    function getCurrentSeason() external view returns (uint256) {
        return currentSeasonId;
    }

    function getMatch(uint256 roundId, uint256 matchIndex)
        external
        view
        returns (Match memory)
    {
        require(matchIndex < MATCHES_PER_ROUND, "Invalid match index");
        return rounds[roundId].matches[matchIndex];
    }

    function getRoundMatches(uint256 roundId) external view returns (Match[] memory) {
        Match[] memory matches = new Match[](MATCHES_PER_ROUND);
        for (uint256 i = 0; i < MATCHES_PER_ROUND; i++) {
            matches[i] = rounds[roundId].matches[i];
        }
        return matches;
    }

    function isRoundSettled(uint256 roundId) external view returns (bool) {
        return rounds[roundId].settled;
    }

    function getTeamStanding(uint256 seasonId, uint256 teamId)
        external
        view
        returns (Team memory)
    {
        return seasonStandings[seasonId][teamId];
    }

    function getSeasonStandings(uint256 seasonId) external view returns (Team[] memory) {
        Team[] memory standings = new Team[](TEAMS_COUNT);
        for (uint256 i = 0; i < TEAMS_COUNT; i++) {
            standings[i] = seasonStandings[seasonId][i];
        }
        return standings;
    }

    function getSeason(uint256 seasonId) external view returns (Season memory) {
        return seasons[seasonId];
    }

    function getRound(uint256 roundId) external view returns (Round memory) {
        return rounds[roundId];
    }

    function getTeam(uint256 teamId) external view returns (Team memory) {
        require(teamId < TEAMS_COUNT, "Invalid team ID");
        return teams[teamId];
    }

    function getRequestStatus(uint256 requestId)
        external
        view
        returns (bool exists, bool fulfilled, uint256 roundId)
    {
        RequestStatus memory request = vrfRequests[requestId];
        return (request.exists, request.fulfilled, request.roundId);
    }

    /**
     * @notice Get test VRF request status and results
     * @param requestId The VRF request ID
     * @return exists Whether the request exists
     * @return fulfilled Whether the request has been fulfilled
     * @return requestTime When the request was made
     * @return randomWords The random words received (empty if not fulfilled)
     */
    function getTestVRFResult(uint256 requestId)
        external
        view
        returns (
            bool exists,
            bool fulfilled,
            uint256 requestTime,
            uint256[] memory randomWords
        )
    {
        TestVRFRequest storage testRequest = testVRFRequests[requestId];
        return (
            testRequest.exists,
            testRequest.fulfilled,
            testRequest.requestTime,
            testRequest.randomWords
        );
    }

    /**
     * @notice Get the last test VRF request ID and its status
     * @return requestId The last test request ID (0 if none)
     * @return exists Whether the request exists
     * @return fulfilled Whether the request has been fulfilled
     * @return requestTime When the request was made
     * @return randomWords The random words received
     */
    function getLastTestVRFResult()
        external
        view
        returns (
            uint256 requestId,
            bool exists,
            bool fulfilled,
            uint256 requestTime,
            uint256[] memory randomWords
        )
    {
        requestId = lastTestRequestId;
        if (requestId == 0) {
            return (0, false, false, 0, new uint256[](0));
        }

        TestVRFRequest storage testRequest = testVRFRequests[requestId];
        return (
            requestId,
            testRequest.exists,
            testRequest.fulfilled,
            testRequest.requestTime,
            testRequest.randomWords
        );
    }

    // Admin functions
    function updateVRFConfig(
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        bytes32 _keyHash
    ) external onlyOwner {
        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
        keyHash = _keyHash;
    }

    /**
     * @notice Test helper: set the VRF request time for a round
     * @dev Allows tests to trigger emergency settlement without requiring a real coordinator
     */
    function setRoundVRFRequestTime(uint256 roundId, uint256 timestamp) external onlyOwner {
        roundVRFRequestTime[roundId] = timestamp;
    }

    /**
     * @notice Withdraw LINK tokens from contract
     */
    function withdrawLink() external onlyOwner {
        require(
            linkToken.transfer(msg.sender, linkToken.balanceOf(address(this))),
            "Unable to transfer"
        );
    }

    /**
     * @notice Withdraw native ETH from contract
     */
    function withdrawNative(uint256 amount) external onlyOwner {
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "withdrawNative failed");
    }

    /**
     * @notice Emergency settlement if VRF fails to respond
     * @dev Can only be called after VRF_TIMEOUT (2 hours) has passed
     */
    function emergencySettleRound(uint256 roundId, uint256 seed) external onlyOwner {
        Round storage round = rounds[roundId];
        require(!round.settled, "Already settled");
        require(
            roundVRFRequestTime[roundId] > 0,
            "VRF not requested yet"
        );
        require(
            block.timestamp >= roundVRFRequestTime[roundId] + VRF_TIMEOUT,
            "VRF timeout not reached - wait 2 hours"
        );

        // Generate pseudo-random results
        uint256[] memory randomWords = new uint256[](20);
        for (uint256 i = 0; i < 20; i++) {
            randomWords[i] = uint256(
                keccak256(abi.encodePacked(
                    seed,
                    block.prevrandao,
                    block.timestamp,
                    roundId,
                    i
                ))
            );
        }

        // Settle matches
        for (uint256 i = 0; i < MATCHES_PER_ROUND; i++) {
            Match storage _match = round.matches[i];

            uint8 homeScore = _generateScore(randomWords[i * 2]);
            uint8 awayScore = _generateScore(randomWords[i * 2 + 1]);

            _match.homeScore = homeScore;
            _match.awayScore = awayScore;
            _match.settled = true;

            if (homeScore > awayScore) {
                _match.outcome = MatchOutcome.HOME_WIN;
            } else if (awayScore > homeScore) {
                _match.outcome = MatchOutcome.AWAY_WIN;
            } else {
                _match.outcome = MatchOutcome.DRAW;
            }

            _updateStandings(round.seasonId, _match);

            emit MatchSettled(
                roundId,
                i,
                _match.homeTeamId,
                _match.awayTeamId,
                homeScore,
                awayScore,
                _match.outcome
            );
        }

        round.settled = true;
        emit RoundSettled(roundId, round.seasonId);

        if (seasons[round.seasonId].currentRound >= ROUNDS_PER_SEASON) {
            _endSeason(round.seasonId);
        }
    }

    /**
     * @notice Accept native ETH for VRF payment
     */
    receive() external payable {}
}
