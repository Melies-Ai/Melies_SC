import sys
import datetime
from decimal import Decimal, getcontext

# Set the precision for Decimal calculations
getcontext().prec = 30

class Stake:
    def __init__(self, owner, amount, multiplier, lock_period):
        self.owner = owner
        self.amount = Decimal(amount)
        self.multiplier = Decimal(multiplier)
        self.rewards = Decimal('0')
        self.start_date = None
        self.lock_period = lock_period
    
    def __str__(self):
        return f"{self.owner}|{self.amount}|{self.multiplier}|{self.rewards}|{self.start_date}|{self.lock_period}"
    
    def __repr__(self):
        return self.__str__()

class StakingSystem:
    def __init__(self, daily_budget):
        self.stakes = []
        self.daily_budget = Decimal(daily_budget)
        self.total_ponderated_stake = Decimal('0')
        self.current_date = datetime.date(2024, 1, 1)

    def add_stake(self, owner, amount, duration_index):
        multipliers = [Decimal('1'), Decimal('1.3'), Decimal('1.6'), Decimal('2.2'), Decimal('3')]
        lock_periods = [0, 90, 180, 365, 365]
        multiplier = multipliers[duration_index]
        lock_period = lock_periods[duration_index]
        
        stake = Stake(owner, amount, multiplier, lock_period)
        stake.start_date = self.current_date
        self.stakes.append(stake)
        self.total_ponderated_stake += Decimal(amount) * multiplier

    def unstake(self, owner, stake_index):
        stakes_by_owner = [s for s in self.stakes if s.owner == owner]
        if 0 <= stake_index < len(stakes_by_owner):
            stake = stakes_by_owner[stake_index]
            if (self.current_date - stake.start_date).days < stake.lock_period:
                return Decimal('0')  # Cannot unstake during lock period
            
            actual_stake_amount = stake.amount + stake.rewards
            self.total_ponderated_stake -= stake.amount * stake.multiplier
            
            main_list_index = self.stakes.index(stake)
            last_stake = stakes_by_owner[-1]
            self.stakes[main_list_index] = last_stake
            self.stakes.remove(last_stake)

            return actual_stake_amount
        return Decimal('0')

    def calculate_rewards(self):
        total_reward = Decimal('0')
        for stake in self.stakes:
            reward = stake.amount * self.daily_budget * stake.multiplier / self.total_ponderated_stake
            total_reward += reward
            if stake.multiplier == 1:
                stake.rewards += reward
            else:
                stake.amount += reward
        self.update_total_ponderated_stake()
        #print(f"{self.total_ponderated_stake:.6f} {total_reward:.6f}")

    def update_total_ponderated_stake(self):
        self.total_ponderated_stake = sum(stake.amount * stake.multiplier for stake in self.stakes)

    def simulate_day(self):
        self.calculate_rewards()
        self.current_date += datetime.timedelta(days=1)
    
    def print_status(self):
        print(f"{self.total_ponderated_stake:.20f}")

def generate_and_simulate_scenario(num_stakers, duration, num_stake, num_unstake):
    system = StakingSystem(daily_budget=Decimal('624657534246.0'))
    actions = []
    stakers = [f"user{i+1}" for i in range(num_stakers)]
    user_stakes = {user: [] for user in stakers}
    lock_periods = [0, 90, 180, 365, 365]

    stake_amounts = [Decimal('100.0e8'), Decimal('200.0e8'), Decimal('300.0e8'), Decimal('200.0e8')]
    #duration_indices = [0, 0, 0, 0]
    duration_indices = [3, 1, 2, 3]


    total_actions = num_stakers * (num_stake + num_unstake)
    action_interval = max(1, duration // total_actions)
    action_queue = []

    day = 1
    for i in range(num_stake):
        counter = 1
        for user in stakers:
            action_queue.append((day, "stake", user, i % 4))
            if(counter % 150 == 0):
                day += action_interval
            counter += 1
    for i in range(num_unstake):
        for user in stakers:
            action_queue.append((day, "unstake", user, i % 4))
            if(counter % 150 == 0):
                day += action_interval
            counter += 1
    
    action_queue = sorted(action_queue, key=lambda x: x[0])
    action_queue = [item for item in action_queue if item[0] <= duration]

    #stake_amounts = [Decimal('1000.0e8'), Decimal('100.0e8'), Decimal('1000.0e8'), Decimal('10000.0e8'), Decimal('1000.0e8')]
    #duration_indices = [2, 0, 1, 4, 3]
    #action_queue = [
    #    (1, "stake", "user2", 0),
    #    (2, "stake", "user1", 1),
    #    (5, "stake", "user4", 2),
    #    (10, "stake", "user3", 3),
    #    (23, "unstake", "user1", 0),
    #    (96, "unstake", "user4", 0),
    #    (108, "stake", "user1", 4),
    #    (196, "unstake", "user2", 0)
    #]

    day = 1
    while action_queue and day <= duration:
        expected_day, action_type, user, index = action_queue.pop(0)

        while expected_day > day and day <= duration:
            system.simulate_day()
            day += 1

        if action_type == "stake":
            amount = stake_amounts[index]
            duration_index = duration_indices[index]
            system.add_stake(user, amount, duration_index)
            user_stakes[user].append((day, amount, duration_index))
            actions.append(f"{day}|stake|{user}|{int(amount)}|{duration_index}")
        elif action_type == "unstake":
            if len(user_stakes[user]) > index:
                stake_day, _, stake_duration_index = user_stakes[user][0]
                lock_period = lock_periods[stake_duration_index]
                if day - stake_day >= lock_period + 1:
                    unstaked_amount = system.unstake(user, 0)
                    if unstaked_amount > 0:
                        actions.append(f"{day}|unstake|{user}|{0}|{0}")
                        user_stakes[user].pop(0)
                else:
                    action_queue.append((stake_day + lock_period + 1, action_type, user, index))
                    action_queue = [item for item in action_queue if item[0] <= duration]
                    action_queue = sorted(action_queue, key=lambda x: x[0])

        if expected_day > day:
            system.simulate_day()
            day += 1

    while day <= duration:
        system.simulate_day()
        day += 1

    actions = [item for item in actions if int(item.split("|")[0]) <= duration]
    return ",".join(actions), int(system.total_ponderated_stake)

if __name__ == "__main__":
    num_stakers = int(sys.argv[1])
    duration = int(sys.argv[2])
    num_stake = int(sys.argv[3])
    num_unstake = int(sys.argv[4])
    scenario, final_ponderated_stake = generate_and_simulate_scenario(num_stakers, duration, num_stake, num_unstake)
    print(f"{scenario}/{final_ponderated_stake}")