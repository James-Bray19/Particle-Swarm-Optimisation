%% Use PSO to optimise PID controllers for a given control system
 
%% Parameters

% transfer function
G = tf([1 1], [1 8 3 2]);

% PSO parameters
maxIterations = 200;       % maximum number of iterations
population = 30;           % number of particles in the swarm
inertiaWeight = 100;       % weight controlling the particle's inertia for momentum
inertiaDamping = 0.99;     % let inertia decrease over time
cognitiveWeight = 5;       % weight for the cognitive (self-awareness) component
cognitiveDecrease = 1;     % let cognitive component decrease over time
socialWeight = 12;         % weight for the social (swarm awareness) component
socialIncrease = 1.02;     % let social component increase over time
maxVelocity = 2;           % maximum speed of particle movement

% control system parameters
min_Kp = 0; max_Kp = 500;
min_Ki = 0; max_Ki = 100;
min_Kd = 0; max_Kd = 100;

%% Particle Initialisation

% give every particle a random position within the domain
swarm = cell(1, population);
for i = 1:population
    swarm{i} = ParticleClass([min_Kp + (max_Kp - min_Kp) * rand, ...
                              min_Ki + (max_Ki - min_Ki) * rand, ...
                              min_Kd + (max_Kd - min_Kd) * rand]);
end

%% Plot Initialisation

% create 3D graph
figure; hold on;
axis([min_Kp max_Kp min_Ki max_Ki min_Kd max_Kd]);
axis square; grid on; view(3);
xlabel('Kp'); ylabel('Ki'); zlabel('Kd');

% initialise plots
bestPlot = plot3(0, 0, 0, 'g.', 'MarkerSize', 15);
particlePlots = gobjects(1, population);
for i = 1:population
    particlePlots(i) = plot3(swarm{i}.position(1), ...
        swarm{i}.position(2), swarm{i}.position(3), 'r.', 'MarkerSize', 10);
end

%% Precompute Variables

% initialise best value
globalBestValue = Inf;

% scale velocity based on controller domains
velocityScaler = [max_Kp - min_Kp, max_Ki - min_Ki, max_Kd - min_Kd];
velocityScaler = velocityScaler / norm(velocityScaler);

%% Main PSO loop

for iteration = 1:maxIterations

    % batch properties for parallel processing
    numBatches = maxNumCompThreads;
    batchSize = ceil(population / numBatches);

    batches = cell(1, numBatches);

    % split swarm apart
    for i = 1:numBatches
        startIdx = (i - 1) * batchSize + 1;
        endIdx = min(i * batchSize, population);
        batches{i} = swarm(startIdx:endIdx);
    end

    % update values
    parfor batchNum = 1:numBatches
        batch = batches{batchNum};

        for i = 1:numel(batch)
            % fetch controllers
            Kp = batch{i}.position(1);
            Ki = batch{i}.position(2);
            Kd = batch{i}.position(3);
            
            % check if particle is in the domain
            if Kp >= min_Kp && Kp <= max_Kp && Ki >= min_Ki && Ki <= max_Ki && Kd >= min_Kd && Kd <= max_Kd
                batch{i}.value = ObjectiveFunction(Kp, Ki, Kd, G);
            else
                batch{i}.value = Inf;
            end
        end
    
        batches{batchNum} = batch;
    end
    
    % Reassign updated batches back to the swarm
    for batchNum = 1:numBatches
        startIdx = (batchNum - 1) * batchSize + 1;
        endIdx = min(batchNum * batchSize, population);
        swarm(startIdx:endIdx) = batches{batchNum};
    end

    % update best values
    for i = 1:population
        p = swarm{i};

        % local values
        if swarm{i}.value < swarm{i}.bestValue
            swarm{i}.bestValue = swarm{i}.value;
            swarm{i}.bestPosition = swarm{i}.position;

            % global values
            if swarm{i}.bestValue <= globalBestValue
                globalBestValue = swarm{i}.bestValue;
                globalBestPosition = swarm{i}.bestPosition;
            end
        end

        swarm{i} = p;
    end

    % move particles
    for i = 1:population
        p = swarm{i};
        
        % calculate velocity
        cognitiveComponent = cognitiveWeight * rand(1, 3) .* (p.bestPosition - p.position);
        socialComponent = socialWeight * rand(1, 3) .* (globalBestPosition - p.position);
        p.velocity = inertiaWeight * p.velocity + cognitiveComponent + socialComponent;
        
        % limit velocity
        velocityNorm = norm(p.velocity);
        if velocityNorm > maxVelocity
            p.velocity = (p.velocity / velocityNorm) * maxVelocity;
        end
        
        % scale velocity and move particles
        p.position = p.position + maxVelocity * p.velocity .* velocityScaler;

        swarm{i} = p;
    end
    
    % change weighting over time
    inertiaWeight = inertiaWeight * inertiaDamping;
    cognitiveWeight = cognitiveWeight * cognitiveDecrease;
    socialWeight = socialWeight * socialIncrease;

    % update best point 
    set(bestPlot, 'XData', globalBestPosition(1), ...
                  'YData', globalBestPosition(2), ...
                  'ZData', globalBestPosition(3));

    % update particle points
    for i = 1:population
        set(particlePlots(i), 'XData', swarm{i}.position(1), ...
                              'YData', swarm{i}.position(2), ...
                              'ZData', swarm{i}.position(3));
    end
    drawnow;
end

%% Output results

% display controllers
Kp = globalBestPosition(1);
Ki = globalBestPosition(2);
Kd = globalBestPosition(3);
disp('Best found PID controller:')
disp(['Kp = ' num2str(Kp)]);
disp(['Ki = ' num2str(Ki)]);
disp(['Kd = ' num2str(Kd)]);

C = tf([Kd Kp Ki], [0 1 0]);
T1 = feedback(G, 1);
T2 = feedback(C*G, 1);

% output improvements
disp(stepinfo(T1));
disp(stepinfo(T2));

% plot step responses
figure;
subplot(1, 2, 1); step(T1); title('Without PID')   
subplot(1, 2, 2); step(T2); title('With PID') 

