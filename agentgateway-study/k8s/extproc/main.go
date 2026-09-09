package main

import (
	"encoding/json"
	"io"
	"log"
	"net"

	extproc "github.com/envoyproxy/go-control-plane/envoy/service/ext_proc/v3"
	typev3 "github.com/envoyproxy/go-control-plane/envoy/type/v3"
	"google.golang.org/grpc"
	"google.golang.org/grpc/health"
	"google.golang.org/grpc/health/grpc_health_v1"
)

// ext_proc 인자 통제 서버: tools/call get-sum은 a==1일 때만 허용. 나머지는 통과.
type server struct{ extproc.UnimplementedExternalProcessorServer }

type rpc struct {
	Method string `json:"method"`
	Params struct {
		Name      string                 `json:"name"`
		Arguments map[string]interface{} `json:"arguments"`
	} `json:"params"`
}

func (s *server) Process(srv extproc.ExternalProcessor_ProcessServer) error {
	for {
		req, err := srv.Recv()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		resp := &extproc.ProcessingResponse{}
		switch v := req.Request.(type) {
		case *extproc.ProcessingRequest_RequestHeaders:
			resp.Response = &extproc.ProcessingResponse_RequestHeaders{RequestHeaders: &extproc.HeadersResponse{}}
		case *extproc.ProcessingRequest_RequestBody:
			deny := false
			var r rpc
			if json.Unmarshal(v.RequestBody.Body, &r) == nil && r.Method == "tools/call" && r.Params.Name == "get-sum" {
				a, ok := r.Params.Arguments["a"].(float64)
				deny = !ok || a != 1
			}
			log.Printf("body method=%s tool=%s deny=%v", r.Method, r.Params.Name, deny)
			if deny {
				resp.Response = &extproc.ProcessingResponse_ImmediateResponse{ImmediateResponse: &extproc.ImmediateResponse{
					Status: &typev3.HttpStatus{Code: typev3.StatusCode_Forbidden},
					Body:   []byte("denied by ext_proc: get-sum is allowed only with a == 1"),
				}}
			} else {
				resp.Response = &extproc.ProcessingResponse_RequestBody{RequestBody: &extproc.BodyResponse{}}
			}
		case *extproc.ProcessingRequest_ResponseHeaders:
			resp.Response = &extproc.ProcessingResponse_ResponseHeaders{ResponseHeaders: &extproc.HeadersResponse{}}
		case *extproc.ProcessingRequest_ResponseBody:
			resp.Response = &extproc.ProcessingResponse_ResponseBody{ResponseBody: &extproc.BodyResponse{}}
		case *extproc.ProcessingRequest_RequestTrailers:
			resp.Response = &extproc.ProcessingResponse_RequestTrailers{}
		case *extproc.ProcessingRequest_ResponseTrailers:
			resp.Response = &extproc.ProcessingResponse_ResponseTrailers{}
		}
		if err := srv.Send(resp); err != nil {
			return err
		}
	}
}

func main() {
	lis, err := net.Listen("tcp", ":18080")
	if err != nil {
		log.Fatal(err)
	}
	g := grpc.NewServer()
	extproc.RegisterExternalProcessorServer(g, &server{})
	grpc_health_v1.RegisterHealthServer(g, health.NewServer())
	log.Println("ext_proc listening :18080")
	log.Fatal(g.Serve(lis))
}
