The EnDAOsment's modular governance framework utilizes a CORE contract that acts as a central hub, dynamically determining which governance module, either an Approval or Quadratic Governor, is invoked based on the current stage of a proposal. This modular design allows for a flexible and adaptable governance system that can evolve with the needs of the DAO. I believe that a decision involves two components: 
 - **Equitable Collective/Communal Value**
 - **Socioeconomically Sustainable Development**

Existing major DAO platforms lack a comprehensive multi-stage decision-making framework. To achieve this, I'd need to significantly customize my own smart contracts, so I might as well build a new platform from scratch. EnDAOsment's modular governance framework provides a robust and adaptable system for managing proposals within the DAO, allowing for different voting mechanisms to be applied based on the specific stage of a proposal and its maturity. 

**Modular Governance**: The framework utilizes a modular design, enabling the interchange and customization of governance components. This avoids the need for forking and rewriting entire contracts when adapting to changing needs or requirements.

<img src="https://github.com/EnDAOsment/DAO-Smart-Contract-Framework/blob/main/EnDAOsmentProcessFlow.svg" alt="EnDAOsment Process Flow">

Here's a breakdown of how this framework would operates:
1. **Governor General** [CORE Contract]: This central contract serves as the entry point for all governance proposals and holds the logic for determining which specific Governor contract to use at each stage of a proposal's lifecycle.
2. **Approval Governor**: This Governor handles proposals in their initial stages, requiring a simple approval threshold (or a designated set of approvers, 2/3) before progressing further. Focus on WHY we should go forward with the proposal.
3. **Quadratic Governor**: This Governor type, implemented using quadratic voting, is employed in the later stages of a proposal, allowing for more nuanced and weighted voting based on participants' preference intensity. Focus on HOW MUCH resources we should allocate and HOW we should implement the proposal.

One of the key limitions among the existing DAOs, in our opinion, is each proposal general stands on its own when, in reality, proposals should be batched together over a single voting period. A proposal should be analogous to electing an official policy-maker/executive, because of Bounded Rationality due to resource limitation, such as Time, Attention, and Information, as well as money and manpower. This means, with a given fiscal period, such as 3 months, there should only be 1 major voting process for everyone to review, discuss, and decide what to move forward with.  

Comparison with major DAO Platforms: 
- Aragon: 
- DAOStack
- Colony
