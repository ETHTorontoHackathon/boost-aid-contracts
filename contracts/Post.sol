// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./IPostFactory.sol";

// Author: @boostaid
contract Post {
    address public owner;
    address payable public parent;
    address payable public questioner;
    address payable public company;
    address[] public answerers;
    uint public questionerBounty;
    uint public companyBounty;
    bool locked = false;
    address payable public winner;

    modifier onlyQuestioner() {
        require(
            msg.sender == questioner,
            "Only the questioner can call this function"
        );
        _;
    }

    modifier noWinnerSelected() {
        require(winner == address(0), "A winner has already been selected");
        _;
    }

    modifier payableCannotBeZero() {
        require(msg.value > 0, "The amount must be greater than 0");
        _;
    }

    modifier payableMustMatchAmount(uint amount) {
        require(msg.value == amount, "Ether sent must match amount specified");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "Reentrant call");
        locked = true;
        _;
        locked = false;
    }

    modifier noAnswers() {
        require(
            answerers.length == 0,
            "Can only be called when there are no answers"
        );
        _;
    }

    modifier onlyCompany() {
        require(
            msg.sender == company,
            "Only the company can call this function"
        );
        _;
    }

    modifier isAnswerer(address answerer) {
        bool foundAnswerer = false;
        for (uint i = 0; i < answerers.length; i++) {
            if (answerers[i] == answerer) {
                foundAnswerer = true;
                break;
            }
        }

        require(foundAnswerer, "Address is not an answerer");
        _;
    }

    // we deploy the contract because we gather funds from company contract and the user
    constructor(
        address _owner,
        address payable _parent,
        address payable _questioner,
        address payable _company,
        uint _questionerBounty,
        uint _companyBounty
    ) payable {
        require(
            _owner != address(0),
            "Owner address cannot be the zero address"
        );
        require(
            _parent != address(0),
            "Parent address cannot be the zero address"
        );
        require(
            _questioner != address(0),
            "Questioner address cannot be the zero address"
        );
        require(
            _company != address(0),
            "Company address cannot be the zero address"
        );
        require(msg.value >= 0, "Bounty must be greater than 0");
        require(
            msg.value == _questionerBounty + _companyBounty,
            "The amount sent must be equal to the sum of the bounties"
        );

        owner = _owner;
        parent = _parent;
        questioner = _questioner;
        company = _company;
        questionerBounty = _questionerBounty;
        companyBounty = _companyBounty;
        IPostFactory(parent).notifyNewQuestionPosted(
            parent,
            address(this),
            questioner,
            company,
            questionerBounty,
            companyBounty
        );
    }

    function increaseQuestionerBounty(
        uint amount
    )
        public
        payable
        onlyQuestioner
        noWinnerSelected
        payableCannotBeZero
        payableMustMatchAmount(amount)
    {
        questionerBounty += amount;
        IPostFactory(parent).notifyQuestionerBountyIncreased(
            address(this),
            questioner,
            amount
        );
    }

    function decreaseQuestionerBounty(
        uint amount
    ) public onlyQuestioner noWinnerSelected noAnswers nonReentrant {
        require(
            questionerBounty >= amount,
            "Amount to be decreased by cannot be greater than the bounty"
        );
        questionerBounty -= amount;
        bool success = questioner.send(amount);
        require(success, "Failed to send ether.");
        IPostFactory(parent).notifyQuestionerBountyDecreased(
            address(this),
            questioner,
            amount
        );
    }

    function increaseCompanyBounty(
        uint amount
    )
        public
        payable
        onlyCompany
        noWinnerSelected
        payableCannotBeZero
        payableMustMatchAmount(amount)
    {
        companyBounty += amount;
        IPostFactory(parent).notifyCompanyBountyIncreased(
            address(this),
            company,
            amount
        );
    }

    function decreaseCompanyBounty(
        uint amount
    ) public onlyCompany noWinnerSelected noAnswers nonReentrant {
        require(
            companyBounty >= amount,
            "Amount to be decreased by cannot be greater than the bounty"
        );
        companyBounty -= amount;
        bool success = company.send(amount);
        require(success, "Failed to send ether.");
        IPostFactory(parent).notifyCompanyBountyDecreased(
            address(this),
            company,
            amount
        );
    }

    function addAnswer() public noWinnerSelected {
        require(
            msg.sender != questioner || msg.sender != company,
            "Only addresses that are not the questioner or company can call this function"
        );

        for (uint i = 0; i < answerers.length; i++) {
            require(
                answerers[i] != msg.sender,
                "Address has already been added as an answerer"
            );
        }

        answerers.push(msg.sender);
        IPostFactory(parent).notifyAnswerAdded(address(this), msg.sender);
    }

    function removeAnswer() public noWinnerSelected isAnswerer(msg.sender) {
        for (uint i = 0; i < answerers.length; i++) {
            if (answerers[i] == msg.sender) {
                answerers[i] = answerers[answerers.length - 1];
                answerers.pop();
                break;
            }
        }

        IPostFactory(parent).notifyAnswerRemoved(address(this), msg.sender);
    }

    function removeQuestion() public noWinnerSelected nonReentrant {
        require(msg.sender == owner, "Only the owner can call this function");

        bool success = company.send(companyBounty);
        require(success, "Failed to send ether back to company.");
        companyBounty = 0;

        success = questioner.send(questionerBounty);
        require(success, "Failed to send ether back to questioner.");
        questionerBounty = 0;

        IPostFactory(parent).notifyQuestionRemoved(address(this));
    }

    function chooseWinner(
        address payable _winner
    ) public onlyQuestioner noWinnerSelected isAnswerer(_winner) nonReentrant {
        winner = _winner;

        uint questionerBountyReward = questionerBounty;
        uint companyBountyReward = companyBounty;

        bool success = winner.send(questionerBounty + companyBounty);
        require(success, "Failed to send ether to winner.");
        questionerBounty = 0;
        companyBounty = 0;

        IPostFactory(parent).notifyWinnerSelected(
            address(this),
            winner,
            questionerBountyReward,
            companyBountyReward
        );
    }

    function getAnswerersLength() public view returns (uint) {
        return answerers.length;
    }
}
