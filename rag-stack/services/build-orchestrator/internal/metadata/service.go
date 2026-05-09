package metadata

import (
	"context"
	"time"

	"app-builds/common/ent"
	"app-builds/common/ent/buildjournal"
	"app-builds/common/ent/buildlock"
	"app-builds/common/ent/buildversion"
)

type Service struct {
	client *ent.Client
}

func NewService(client *ent.Client) *Service {
	return &Service{client: client}
}

type VersionInfo struct {
	ServiceName string    `json:"service_name"`
	Version     string    `json:"version"`
	LastBuild   time.Time `json:"last_build"`
}

func (s *Service) GetVersions(ctx context.Context) ([]VersionInfo, error) {
	versions, err := s.client.BuildVersion.Query().All(ctx)
	if err != nil {
		return nil, err
	}
	res := make([]VersionInfo, len(versions))
	for i, v := range versions {
		res[i] = VersionInfo{
			ServiceName: v.ServiceName,
			Version:     v.Version,
			LastBuild:   v.LastBuild,
		}
	}
	return res, nil
}

func (s *Service) GetVersion(ctx context.Context, serviceName string) (*VersionInfo, error) {
	v, err := s.client.BuildVersion.Query().
		Where(buildversion.ServiceNameEQ(serviceName)).
		Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return nil, nil
		}
		return nil, err
	}
	return &VersionInfo{
		ServiceName: v.ServiceName,
		Version:     v.Version,
		LastBuild:   v.LastBuild,
	}, nil
}

func (s *Service) UpdateVersion(ctx context.Context, serviceName, version string) error {
	return s.client.BuildVersion.Create().
		SetServiceName(serviceName).
		SetVersion(version).
		SetLastBuild(time.Now()).
		OnConflictColumns(buildversion.FieldServiceName).
		UpdateVersion().
		UpdateLastBuild().
		Exec(ctx)
}

type LockInfo struct {
	ServiceName string    `json:"service_name"`
	Owner       string    `json:"lock_owner"`
	PID         int       `json:"lock_pid"`
	Host        string    `json:"lock_host"`
	AcquiredAt  time.Time `json:"acquired_at"`
	Heartbeat   time.Time `json:"heartbeat"`
}

func (s *Service) AcquireLock(ctx context.Context, serviceName, owner, host string, pid int) (bool, *LockInfo, error) {
	// Try to create the lock
	err := s.client.BuildLock.Create().
		SetServiceName(serviceName).
		SetLockOwner(owner).
		SetLockHost(host).
		SetLockPid(pid).
		SetAcquiredAt(time.Now()).
		SetHeartbeat(time.Now()).
		Exec(ctx)

	if err == nil {
		return true, nil, nil
	}

	// If failed, check if it's expired (e.g. 2 minutes without heartbeat)
	lock, err := s.client.BuildLock.Query().
		Where(buildlock.ServiceNameEQ(serviceName)).
		Only(ctx)
	if err != nil {
		return false, nil, err
	}

	if time.Since(lock.Heartbeat) > 2*time.Minute {
		// Stale lock, force release and try again
		_ = s.client.BuildLock.DeleteOne(lock).Exec(ctx)
		return s.AcquireLock(ctx, serviceName, owner, host, pid)
	}

	return false, &LockInfo{
		ServiceName: lock.ServiceName,
		Owner:       lock.LockOwner,
		PID:         lock.LockPid,
		Host:        lock.LockHost,
		AcquiredAt:  lock.AcquiredAt,
		Heartbeat:   lock.Heartbeat,
	}, nil
}

func (s *Service) ReleaseLock(ctx context.Context, serviceName string) error {
	_, err := s.client.BuildLock.Delete().
		Where(buildlock.ServiceNameEQ(serviceName)).
		Exec(ctx)
	return err
}

func (s *Service) CheckLock(ctx context.Context, serviceName string) (*LockInfo, error) {
	lock, err := s.client.BuildLock.Query().
		Where(buildlock.ServiceNameEQ(serviceName)).
		Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return nil, nil
		}
		return nil, err
	}
	return &LockInfo{
		ServiceName: lock.ServiceName,
		Owner:       lock.LockOwner,
		PID:         lock.LockPid,
		Host:        lock.LockHost,
		AcquiredAt:  lock.AcquiredAt,
		Heartbeat:   lock.Heartbeat,
	}, nil
}

func (s *Service) Heartbeat(ctx context.Context, serviceName string) error {
	return s.client.BuildLock.Update().
		Where(buildlock.ServiceNameEQ(serviceName)).
		SetHeartbeat(time.Now()).
		Exec(ctx)
}

func (s *Service) ResetLocks(ctx context.Context) error {
	_, err := s.client.BuildLock.Delete().Exec(ctx)
	return err
}

func (s *Service) GetJournal(ctx context.Context, serviceName string) (string, error) {
	j, err := s.client.BuildJournal.Query().
		Where(buildjournal.ServiceNameEQ(serviceName)).
		Only(ctx)
	if err != nil {
		if ent.IsNotFound(err) {
			return "", nil
		}
		return "", err
	}
	return j.LastHash, nil
}

func (s *Service) UpdateJournal(ctx context.Context, serviceName, hash string) error {
	return s.client.BuildJournal.Create().
		SetServiceName(serviceName).
		SetLastHash(hash).
		SetUpdatedAt(time.Now()).
		OnConflictColumns(buildjournal.FieldServiceName).
		UpdateLastHash().
		UpdateUpdatedAt().
		Exec(ctx)
}
